defmodule Brando.SEO.Generate do
  @moduledoc """
  Generates an entry's meta description or title from the entry's own content.

  The prompt is whatever the blueprint declares for the field —
  `trait :meta, ai: [meta_description: [prompt: "…", context: [:title, :blocks]]]`
  — falling back to a built-in prompt that asks for a description of display
  length in the entry's language. The context fields are whatever the caller
  passes (the Content SEO tab passes the site's stored pick), the blueprint's
  own `:context` declaration otherwise, and the schema's text and block fields
  when neither says anything.

  Nothing here checks whether AI is configured: `Brando.AI.generate_text/2`
  refuses on its own, and the admin hides the actions behind
  `Brando.AI.configured?/1` so the failure is not something an editor can reach.
  """

  alias Brando.AI
  alias Brando.AI.Context

  @fields [:meta_description, :meta_title]
  # What the default prompt asks for — comfortably inside what the audit calls
  # a good length — and the hard cap a reply is cut back to, which is that
  # audit's upper bound (`Brando.SEO.Checks`). A model that overshoots by a few
  # characters is left alone; one that writes an essay is not.
  @description_length 155
  @description_cap 160
  @title_length 60
  @title_cap 60
  # Enough of the entry for the model to describe it; more is mostly navigation
  # and footers repeated across every page.
  @context_length 2000

  @doc """
  Generates `field` for one entry and writes it.

  Returns `{:ok, %{text: text, entry: entry}}` with the updated entry, so the
  caller can re-score the row it came from without reading it again.

  ## Options

    * `:context_fields` — the fields the prompt reads. Defaults to the stored
      picker selection, then the blueprint's declaration.
    * `:persist` — set to `false` to return the text without writing it.
  """
  @spec generate(module(), integer() | String.t(), atom(), map() | atom(), keyword()) ::
          {:ok, %{text: String.t(), entry: map() | nil}} | {:error, term()}
  def generate(schema, id, field \\ :meta_description, user \\ :system, opts \\ [])

  def generate(_schema, _id, field, _user, _opts) when field not in @fields,
    do: {:error, :unsupported_field}

  def generate(schema, id, field, user, opts) do
    with {:ok, entry} <- fetch(schema, id),
         {:ok, prompt, ai_opts} <- prompt_for(schema, entry, field, opts),
         {:ok, %{text: text}} <- AI.generate_text(prompt, ai_opts) do
      text = trim_to_length(text, field)

      if Keyword.get(opts, :persist, true) do
        with {:ok, entry} <- persist(schema, id, field, text, user) do
          {:ok, %{text: text, entry: entry}}
        end
      else
        {:ok, %{text: text, entry: entry}}
      end
    end
  end

  @doc """
  The prompt `field` would be generated from, and the AI options it runs under.

  Split out from `generate/5` so the prompt can be inspected — and tested —
  without spending a request on it.
  """
  @spec prompt_for(module(), map(), atom(), keyword()) ::
          {:ok, String.t(), keyword()} | {:error, term()}
  def prompt_for(schema, entry, field, opts \\ []) do
    ai_opts = AI.field_ai_opts(schema, field)
    fields = Keyword.get(opts, :context_fields) || context_fields(schema, ai_opts)
    values = Context.for_entry(entry, fields, length: @context_length)

    case values do
      [] -> {:error, :no_context}
      values -> {:ok, Context.build_prompt(prompt(ai_opts, entry, field), values), ai_opts}
    end
  end

  @doc """
  The fields a prompt for `schema` reads, most specific source first: the
  blueprint's own `:context` declaration, then every text and block field the
  schema has.
  """
  @spec context_fields(module(), keyword()) :: [atom()]
  def context_fields(schema, ai_opts \\ []) do
    case ai_opts |> Keyword.get(:context, []) |> Context.normalize_fields() do
      [] -> Context.available_fields(schema)
      fields -> fields
    end
  end

  @doc """
  The context fields stored for `schema` in the site's SEO settings, or `nil`
  when the site has never picked any.

  Stored per schema on `Brando.Sites.SEO` so the choice survives a deploy and
  can be changed without one.
  """
  @spec stored_context_fields(module(), String.t() | atom()) :: [atom()] | nil
  def stored_context_fields(schema, language) do
    language |> stored() |> pick(schema)
  end

  @doc """
  What every schema in `schemas` reads, resolved in one pass: the site's stored
  pick where there is one, the blueprint's declaration everywhere else.
  """
  @spec context_field_map([module()], String.t() | atom()) :: %{module() => [atom()]}
  def context_field_map(schemas, language) do
    stored = stored(language)
    Map.new(schemas, fn schema -> {schema, pick(stored, schema) || context_fields(schema)} end)
  end

  defp stored(language) do
    case Brando.Sites.get_seo(%{matches: %{language: to_string(language)}}) do
      {:ok, %{ai_context_fields: stored}} when is_map(stored) -> stored
      _ -> %{}
    end
  end

  defp pick(stored, schema) do
    with fields when is_list(fields) <- Map.get(stored, inspect(schema)),
         [_ | _] = fields <- Context.normalize_fields(fields) do
      fields
    else
      _ -> nil
    end
  end

  @doc "Stores the context fields to use for `schema` in `language`."
  @spec store_context_fields(module(), String.t() | atom(), [atom() | String.t()], map() | atom()) ::
          {:ok, map()} | {:error, term()}
  def store_context_fields(schema, language, fields, user) do
    with {:ok, seo} <- Brando.Sites.get_seo(%{matches: %{language: to_string(language)}}) do
      stored = seo.ai_context_fields || %{}
      fields = Enum.map(fields, &to_string/1)

      stored =
        if fields == [],
          do: Map.delete(stored, inspect(schema)),
          else: Map.put(stored, inspect(schema), fields)

      Brando.Sites.update_seo(seo.id, %{ai_context_fields: stored}, user)
    end
  end

  defp fetch(schema, id) do
    context = schema.__modules__().context
    singular = schema.__naming__().singular

    case apply(context, :"get_#{singular}", [%{matches: %{id: id}}]) do
      {:ok, entry} -> {:ok, entry}
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  defp persist(schema, id, field, text, user) do
    context = schema.__modules__().context
    singular = schema.__naming__().singular

    apply(context, :"update_#{singular}", [id, %{field => text}, user])
  end

  @doc """
  The prompt used for `field` when the blueprint declares none of its own.

  Blueprints that care — `Brando.Pages.Page` among them — say what they want
  through `trait :meta, ai: [...]`; this is what everything else gets.
  """
  @spec default_prompt(map(), atom()) :: String.t()
  def default_prompt(entry, field)

  def default_prompt(entry, :meta_description) do
    """
    Write the meta description for this page in #{language_name(entry)}. One \
    sentence of at most #{@description_length} characters that tells someone \
    scanning search results what the page is about. Plain text, no quotes, no \
    site name, no call to action. Reply with the description only.\
    """
  end

  def default_prompt(entry, :meta_title) do
    """
    Write the meta title for this page in #{language_name(entry)}. At most \
    #{@title_length} characters, describing the page rather than the site. \
    Plain text, no quotes, no site name. Reply with the title only.\
    """
  end

  defp prompt(ai_opts, entry, field) do
    case ai_opts |> Keyword.get(:prompt) |> to_trimmed() do
      "" -> default_prompt(entry, field)
      prompt -> prompt
    end
  end

  # A description cut mid-word reads worse than one cut a word early.
  defp trim_to_length(text, field) do
    text = text |> to_trimmed() |> String.trim(~s(")) |> String.trim()
    limit = if field == :meta_title, do: @title_cap, else: @description_cap

    if String.length(text) <= limit do
      text
    else
      text
      |> String.slice(0, limit)
      |> String.replace(~r/\s+\S*$/u, "")
      |> String.trim_trailing(",")
      |> String.trim()
    end
  end

  defp language_name(entry) do
    entry
    |> Map.get(:language)
    |> Kernel.||(Brando.config(:default_language))
    |> AI.language_name()
  end

  defp to_trimmed(value) when is_binary(value), do: String.trim(value)
  defp to_trimmed(_), do: ""
end
