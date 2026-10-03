defmodule Brando.Forms do
  @moduledoc """
  Forms visitors fill in on the site. See `Brando.Forms.Form`, and the
  [Forms guide](forms.md) for rendering and submissions.
  """
  use Brando.Query
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Content.BlockReferences
  alias Brando.Content.Blocks
  alias Brando.Forms.Field
  alias Brando.Forms.Form
  alias Brando.Forms.Messages
  alias Brando.Forms.RateLimit
  alias Brando.Forms.Submission
  alias Brando.Forms.Turnstile
  alias Brando.Forms.Validation
  alias Brando.Repo

  query :list, Form, do: fn query -> from(q in query) end

  filters Form do
    fn
      {:title, title}, query ->
        from q in query, where: ilike(q.title, ^"%#{title}%")

      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end

  query :single, Form, do: fn query -> from(q in query) end

  matches Form do
    fn
      {:id, id}, query ->
        from q in query, where: q.id == ^id

      {:key, key}, query ->
        from q in query, where: q.key == ^key

      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end

  mutation :create, Form

  mutation :update, {Form, preload: [:fields]} do
    fn form ->
      render_entries_using_form(form)
      {:ok, form}
    end
  end

  mutation :delete, Form do
    fn form ->
      render_entries_using_form(form)
      {:ok, form}
    end
  end

  # A copy in the same language needs its own key; fields keep theirs.
  mutation :duplicate,
           {Form,
            preload: [:fields],
            change_fields: [
              :title,
              {:key, &__MODULE__.duplicate_key/2},
              alternates: [],
              alternate_entries: []
            ]}

  @doc false
  def duplicate_key(_entry, key), do: "#{key}_copy"

  @doc """
  The published form with `key` in `language`, with its fields, or nil.
  """
  @spec get_published_form(String.t(), String.t() | atom() | nil) :: Form.t() | nil
  def get_published_form(key, language) when is_binary(key) do
    matches = if language, do: %{key: key, language: to_string(language)}, else: %{key: key}

    case get_form(%{matches: matches, status: :published, preload: [:fields]}) do
      {:ok, form} -> form
      _ -> nil
    end
  end

  def get_published_form(_key, _language), do: nil

  @doc "Every language of the form `key`, oldest first, with their fields."
  def list_forms_by_key(key) do
    Repo.all(from f in Form, where: f.key == ^key, order_by: [asc: f.id], preload: [:fields])
  end

  @doc """
  Re-renders the entries whose blocks hold `form` — in any language — in a
  form var, so their stored HTML shows its fields as they are now.
  """
  def render_entries_using_form(%Form{key: key}) do
    render_entries_using_forms(Repo.all(from f in Form, where: f.key == ^key, select: f.id))
  end

  defp render_entries_using_forms(form_ids) do
    form_ids
    |> BlockReferences.list_block_ids_using_forms()
    |> Blocks.list_root_block_ids_by_source()
    |> Blocks.list_entry_ids_for_root_blocks_by_source()
    |> Blocks.enqueue_entry_map_for_render()
  end

  # -- Submissions ------------------------------------------------------------

  @doc """
  Checks and stores what a visitor sent with the published form `key`.

  `params` are the posted parameters: the values under `"fields"`, the form's
  language under `"_language"`, the Turnstile token and the honeypot. `meta`
  carries `:ip`, `:user_agent` and `:url`.

  A filled-in honeypot returns `{:ok, :ignored}`, the same as a success to the
  sender, and stores nothing.
  """
  @spec submit(String.t(), map(), map()) ::
          {:ok, Submission.t() | :ignored, Form.t()}
          | {:error, :not_found}
          | {:error, :rate_limited | :rejected, Form.t()}
          | {:error, {:invalid, map()}, Form.t()}
  def submit(key, params, meta) do
    with %Form{} = form <- get_published_form(key, params["_language"]) || {:error, :not_found},
         :ok <- check_honeypot(params, form),
         :ok <- tag(RateLimit.hit(Submission.current_scope(), form.key, ip_hash(meta[:ip])), form),
         :ok <- tag(verify_turnstile(params, meta), form),
         {:ok, data} <- tag(Validation.validate(form, params["fields"] || %{}), form),
         {:ok, submission} <- insert_submission(form, data, meta) do
      {:ok, submission, form}
    else
      {:ignored, form} -> {:ok, :ignored, form}
      other -> other
    end
  end

  defp check_honeypot(%{"_hp" => value}, form) when is_binary(value) and value != "", do: {:ignored, form}
  defp check_honeypot(_params, _form), do: :ok

  defp verify_turnstile(params, meta) do
    case Turnstile.verify(params["cf-turnstile-response"], meta[:ip]) do
      :ok -> :ok
      {:error, _reason} -> {:error, :rejected}
    end
  end

  defp tag(:ok, _form), do: :ok
  defp tag({:ok, _} = ok, _form), do: ok
  defp tag({:error, {:invalid, _} = reason}, form), do: {:error, reason, form}
  defp tag({:error, errors}, form) when is_map(errors), do: {:error, {:invalid, errors}, form}
  defp tag({:error, reason}, form), do: {:error, reason, form}

  defp insert_submission(form, data, meta) do
    labels =
      for %Field{type: type, key: key, label: label} <- form.fields, type != :section, into: %{}, do: {key, label}

    Repo.insert(%Submission{
      scope: Submission.current_scope(),
      form_id: form.id,
      form_key: form.key,
      language: to_string(form.language),
      data: data,
      labels: labels,
      url: truncate(meta[:url], 2000),
      ip_hash: ip_hash(meta[:ip]),
      user_agent: truncate(meta[:user_agent], 500)
    })
  end

  @doc "A one-way hash of a visitor's IP address, salted with the endpoint secret."
  def ip_hash(nil), do: nil

  def ip_hash(ip) do
    salt = Brando.endpoint().config(:secret_key_base) || ""
    :sha256 |> :crypto.hash([salt, to_string(ip)]) |> Base.encode16(case: :lower) |> binary_part(0, 32)
  end

  defp truncate(nil, _), do: nil
  defp truncate(value, max), do: String.slice(to_string(value), 0, max)

  @doc """
  The submissions of the form `key`, in every language, newest first.

  Options: `:language`, `:limit` and `:offset`.
  """
  def list_submissions(key, opts \\ []) do
    key
    |> submissions_query(opts[:language])
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> Repo.all()
  end

  @doc "How many submissions the form `key` has, in every language or in `language`."
  def count_submissions(key, language \\ nil) do
    key |> submissions_query(language) |> Repo.aggregate(:count)
  end

  @doc "Every submission of the form `key`, oldest first, for an export."
  def stream_submissions(key, language \\ nil) do
    key |> submissions_query(language) |> order_by([s], asc: s.inserted_at, asc: s.id) |> Repo.all()
  end

  @doc "A submission of the form `key` in the current scope."
  def get_submission(key, id) do
    key |> submissions_query(nil) |> where([s], s.id == ^id) |> Repo.one()
  end

  @doc "Deletes a submission of the form `key`."
  def delete_submission(key, id) do
    case get_submission(key, id) do
      nil -> {:error, :not_found}
      submission -> Repo.delete(submission)
    end
  end

  defp submissions_query(key, language) do
    scope = Submission.current_scope()
    query = from s in Submission, where: s.scope == ^scope and s.form_key == ^key
    if language, do: where(query, [s], s.language == ^to_string(language)), else: query
  end

  @doc "The message shown once `form` has been sent: its own, or the site's."
  def success_message(%Form{success_message: message}) when is_binary(message) and message != "", do: message
  def success_message(%Form{language: language}), do: message(:success_message, language)

  # -- Messages ---------------------------------------------------------------

  query :single, Messages, do: fn query -> from(q in query) end

  matches Messages do
    fn
      {:id, id}, query -> from q in query, where: q.id == ^id
    end
  end

  mutation :create, Messages

  # The messages are in the stored HTML of every block holding a form.
  mutation :update, Messages do
    fn messages ->
      render_entries_using_forms(Repo.all(from f in Form, select: f.id))
      {:ok, messages}
    end
  end

  @doc """
  The site's message `key` (see `Brando.Forms.Messages`) in `language`: as the
  site words it, or Brando's own wording when the site has left it empty.
  """
  @spec message(atom(), String.t() | atom() | nil) :: String.t()
  def message(key, language) do
    texts =
      case site_messages() do
        %Messages{} = messages -> Map.get(messages, key) || %{}
        _ -> %{}
      end

    case texts[to_string(language)] do
      text when is_binary(text) and text != "" -> text
      _ -> Messages.built_in(key, language)
    end
  end

  # One row, read when a form renders and when one is sent.
  defp site_messages, do: Repo.one(from m in Messages, order_by: [asc: m.id], limit: 1)

  @doc """
  The site's messages, created on first use with Brando's wording in the
  content languages Brando has translations for.
  """
  def ensure_messages(user) do
    case site_messages() do
      nil ->
        languages = :languages |> Brando.config() |> List.wrap() |> Enum.map(&to_string(&1[:value]))
        create_messages(Messages.prefilled(languages), user)

      messages ->
        {:ok, messages}
    end
  end
end
