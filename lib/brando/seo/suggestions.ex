defmodule Brando.SEO.Suggestions do
  @moduledoc """
  Bulk meta descriptions, written in the background and reviewed before use.

  `enqueue/4` records a `:queued` suggestion per entry and one
  `Brando.Worker.SEOSuggestionGenerator` job each. A job writes the text into
  its suggestion — never into the entry — and announces it on `topic/0`, so
  the Content SEO tab can show progress and the review list as they fill in.
  Accepting a suggestion writes it through the entry's own context, the same
  way the single-entry action does.

  Runs are capped, because every entry is a paid request:

      config :brando, Brando.SEO, max_batch: 200
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.SEO.Audit.Row
  alias Brando.SEO.Generate
  alias Brando.SEO.Suggestion
  alias Brando.Worker.SEOSuggestionGenerator

  @max_batch 200
  @open [:queued, :pending, :failed]

  @doc "The most entries one run will send to the model."
  @spec max_batch() :: pos_integer()
  def max_batch do
    :brando |> Application.get_env(Brando.SEO, []) |> Keyword.get(:max_batch, @max_batch)
  end

  @doc "PubSub topic the generator announces finished suggestions on, per tenant."
  @spec topic() :: String.t()
  def topic, do: "seo-suggestions:#{Brando.Tenant.current_prefix() || "public"}"

  @doc false
  def broadcast(language) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic(), {:seo_suggestions_updated, language})
  end

  @doc """
  Queues a meta description for each of `rows` — at most `max_batch/0` — in
  `language`. Rows with a suggestion already queued or awaiting review are
  skipped; anything else (rejected, failed, accepted and since cleared) is
  asked for again.

  Returns `{:ok, count}` with the number of jobs queued.
  """
  @spec enqueue([Row.t()], String.t(), map() | atom(), keyword()) :: {:ok, non_neg_integer()}
  def enqueue(rows, language, user, opts \\ []) do
    field = Keyword.get(opts, :field, :meta_description)
    language = to_string(language)
    waiting = waiting_keys(language, field)
    now = NaiveDateTime.utc_now(:second)

    rows =
      rows
      |> Enum.reject(&MapSet.member?(waiting, {inspect(&1.schema), &1.id}))
      |> Enum.take(max_batch())

    jobs =
      Enum.map(rows, fn row ->
        suggestion =
          Brando.Repo.insert!(
            %Suggestion{
              schema: inspect(row.schema),
              entry_id: row.id,
              language: language,
              field: field,
              title: row.title,
              status: :queued,
              requested_by_id: user_id(user)
            },
            on_conflict: [
              set: [
                status: :queued,
                title: row.title,
                text: nil,
                model: nil,
                error: nil,
                generated_at: nil,
                requested_by_id: user_id(user),
                reviewed_by_id: nil,
                updated_at: now
              ]
            ],
            conflict_target: [:schema, :entry_id, :language, :field],
            returning: true
          )

        %{"suggestion_id" => suggestion.id}
        |> Brando.Tenant.Job.attach()
        |> SEOSuggestionGenerator.new()
      end)

    Oban.insert_all(jobs)
    {:ok, length(rows)}
  end

  @doc """
  Suggestions in `language` that still need attention: queued, pending
  review, or failed. `fields` narrows them to those fields.
  """
  @spec list_open(String.t(), [atom()] | nil) :: [Suggestion.t()]
  def list_open(language, fields \\ nil) do
    query =
      from s in Suggestion,
        where: s.language == ^to_string(language) and s.status in ^@open,
        order_by: [asc: s.title, asc: s.id]

    query = if fields, do: from(s in query, where: s.field in ^fields), else: query
    Brando.Repo.all(query)
  end

  @doc "Fills in a queued suggestion with generated text."
  @spec fill(Suggestion.t(), String.t(), String.t() | nil) :: {:ok, Suggestion.t()} | {:error, Ecto.Changeset.t()}
  def fill(%Suggestion{} = suggestion, text, model) do
    suggestion
    |> Suggestion.changeset(%{
      text: text,
      model: model,
      status: :pending,
      error: nil,
      generated_at: DateTime.utc_now(:second)
    })
    |> Brando.Repo.update()
  end

  @doc "Marks a suggestion as failed, keeping a message an editor can read."
  @spec fail(Suggestion.t(), String.t()) :: {:ok, Suggestion.t()} | {:error, Ecto.Changeset.t()}
  def fail(%Suggestion{} = suggestion, message) do
    suggestion
    |> Suggestion.changeset(%{status: :failed, error: message})
    |> Brando.Repo.update()
  end

  @doc """
  Writes a pending suggestion to its entry, as `user`, and marks it accepted.
  `text` overrides the suggested text when the editor changed it first.
  """
  @spec accept(integer() | String.t(), String.t() | nil, map()) :: {:ok, Suggestion.t()} | {:error, term()}
  def accept(id, text, user) do
    with {:ok, suggestion} <- get_pending(id),
         {:ok, schema} <- schema(suggestion),
         text = text |> Kernel.||(suggestion.text) |> String.trim(),
         true <- text != "" or {:error, :empty},
         {:ok, _entry} <- write(schema, suggestion, text, user) do
      suggestion
      |> Suggestion.changeset(%{status: :accepted, text: text, reviewed_by_id: user_id(user)})
      |> Brando.Repo.update()
    end
  end

  @doc """
  Accepts every pending suggestion in `language` — for `fields`, when given —
  as written. Returns `{accepted, failed}`.
  """
  @spec accept_all(String.t(), map(), [atom()] | nil) :: {non_neg_integer(), non_neg_integer()}
  def accept_all(language, user, fields \\ nil) do
    language
    |> list_open(fields)
    |> Enum.filter(&(&1.status == :pending))
    |> Enum.reduce({0, 0}, fn suggestion, {accepted, failed} ->
      case accept(suggestion.id, nil, user) do
        {:ok, _} -> {accepted + 1, failed}
        _ -> {accepted, failed + 1}
      end
    end)
  end

  @doc "Rejects a pending suggestion, or dismisses a failed one. The entry is left alone."
  @spec reject(integer() | String.t(), map()) :: {:ok, Suggestion.t()} | {:error, term()}
  def reject(id, user) do
    case Brando.Repo.get(Suggestion, id) do
      %Suggestion{status: status} = suggestion when status in [:pending, :failed] ->
        suggestion
        |> Suggestion.changeset(%{status: :rejected, reviewed_by_id: user_id(user)})
        |> Brando.Repo.update()

      _ ->
        {:error, :not_found}
    end
  end

  # Meta fields go through Generate's writer; alt text through the image's own
  # context. Both are the entry's normal update, as the reviewing user.
  defp write(schema, %Suggestion{field: :alt} = suggestion, text, user) do
    context = schema.__modules__().context
    apply(context, :"update_#{schema.__naming__().singular}", [suggestion.entry_id, %{alt: text}, user])
  end

  defp write(schema, suggestion, text, user),
    do: Generate.write(schema, suggestion.entry_id, suggestion.field, text, user)

  defp get_pending(id) do
    case Brando.Repo.get(Suggestion, id) do
      %Suggestion{status: :pending} = suggestion -> {:ok, suggestion}
      _ -> {:error, :not_found}
    end
  end

  defp schema(suggestion) do
    case Suggestion.schema_module(suggestion) do
      nil -> {:error, :unknown_schema}
      schema -> {:ok, schema}
    end
  end

  defp waiting_keys(language, field) do
    from(s in Suggestion,
      where: s.language == ^language and s.field == ^field and s.status in [:queued, :pending],
      select: {s.schema, s.entry_id}
    )
    |> Brando.Repo.all()
    |> MapSet.new()
  end

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
