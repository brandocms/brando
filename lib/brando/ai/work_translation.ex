defmodule Brando.AI.WorkTranslation do
  @moduledoc """
  Translates a synchronized translation's open work units
  (`Brando.Translations.Work`) with the configured AI model, and returns the
  texts for the entry form to fill in. Nothing is written: the editor reads
  the texts, corrects them and saves.

  A *translate* unit sends the source's text. A *review* unit sends the
  source's current text with the translation's current text, and the model
  is asked to bring the translation up to date rather than write it anew.
  Where the unit has the source's text before the change (`source_previous`),
  it is sent too, and the model is asked for the smallest change to the
  translation that follows the source's change.

  Units are sent in batches of at most `:batch_chars` characters (12,000 by
  default), as JSON, so text over several lines and its markup arrive whole,
  and the reply is a JSON object of texts by item. Each text is checked as
  `Brando.Translations.Work.answer_problems/2` checks an answer: a text that
  lost the source's HTML tags or template placeholders, or that the reply
  left out, is returned as a problem for its unit instead of a text.
  """
  alias Brando.Translations.Work

  @batch_chars 12_000
  @max_tokens 16_000

  @type result :: %{texts: %{String.t() => String.t()}, problems: %{String.t() => [Work.problem()]}}

  @doc """
  Translates the answerable `units` with text from `source_language` into
  `target_language`.

  Options: `:progress`, a function called with `{batches_done, batches}`
  before the first batch and after each; `:batch_chars`; `:ai_opts` for
  `Brando.AI.generate_text/2`.

  Returns `{:ok, %{texts: texts, problems: problems}}`, both by unit key, or
  `{:error, reason}` when a call fails or a reply cannot be read: then
  nothing is returned.
  """
  @spec translate([Work.unit()], String.t(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def translate(units, source_language, target_language, opts \\ []) do
    progress = Keyword.get(opts, :progress, fn _step -> :ok end)
    units = Enum.filter(units, &translatable?/1)
    batches = batches(units, Keyword.get(opts, :batch_chars, @batch_chars))
    total = length(batches)
    progress.({0, total})

    batches
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{texts: %{}, problems: %{}}}, fn {batch, done}, {:ok, acc} ->
      case translate_batch(batch, source_language, target_language, opts) do
        {:ok, replies} ->
          progress.({done, total})
          {:cont, {:ok, Enum.reduce(batch, acc, &collect(&1, replies, &2))}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  @doc "Whether a unit is sent: answerable, with a source text that is not blank."
  def translatable?(%{answerable: true, source: source}) when is_binary(source), do: String.trim(source) != ""
  def translatable?(_unit), do: false

  defp collect({unit, id}, replies, acc) do
    case Map.fetch(replies, id) do
      {:ok, text} when is_binary(text) ->
        case Work.answer_problems(unit, text) do
          [] -> put_in(acc, [:texts, unit.key], text)
          problems -> put_in(acc, [:problems, unit.key], problems)
        end

      _ ->
        put_in(acc, [:problems, unit.key], [
          %{key: unit.key, code: "missing", message: "The reply has no text for this unit."}
        ])
    end
  end

  # Units numbered within their batch, at least one unit per batch
  defp batches(units, limit) do
    units
    |> Enum.chunk_while(
      {[], 0},
      fn unit, {batch, size} ->
        unit_size =
          String.length(unit.source) + String.length(Map.get(unit, :current) || "") +
            String.length(previous_source(unit) || "")

        if batch != [] and size + unit_size > limit,
          do: {:cont, Enum.reverse(batch), {[unit], unit_size}},
          else: {:cont, {[unit | batch], size + unit_size}}
      end,
      fn
        {[], _} -> {:cont, {[], 0}}
        {batch, _} -> {:cont, Enum.reverse(batch), {[], 0}}
      end
    )
    |> Enum.map(fn batch -> batch |> Enum.with_index(1) |> Enum.map(fn {unit, n} -> {unit, to_string(n)} end) end)
  end

  defp translate_batch(batch, source_language, target_language, opts) do
    {system_prompt, prompt} = prompt(batch, source_language, target_language)
    ai_opts = Keyword.merge([system_prompt: system_prompt, max_tokens: @max_tokens], Keyword.get(opts, :ai_opts, []))

    with {:ok, %{text: text}} <- Brando.AI.generate_text(prompt, ai_opts) do
      parse(text)
    end
  end

  @doc """
  The system prompt and the prompt for a batch of `{unit, id}`: the items as
  JSON, each with its `format`, the `source` and, for a review, the
  `translation` to bring up to date, with the source's text before the
  change (`previous_source`) where it is known.
  """
  def prompt(batch, source_language, target_language) do
    source_name = Brando.AI.language_name(source_language)
    target_name = Brando.AI.language_name(target_language)

    system_prompt = """
    You are a professional translator. Translate website content from #{source_name} to #{target_name}.

    Each item has a number (n), a format (plain, html or markdown) and the source text.
    An item with a "translation" is an existing #{target_name} translation of an earlier version of the source: \
    bring it up to date with the source as it is now. Keep its wording where the source did not change, \
    and change only what the source's changes need.
    When such an item also has a "previous_source", the source text the translation was made from, make the \
    smallest change to the translation that follows the change from previous_source to source, and keep the rest \
    of the translation word for word.

    RULES:
    - Keep every HTML tag in order, with its attributes exactly as they are; translate only the text between tags
    - Keep Markdown syntax as it is
    - Keep template placeholders such as {{ name }}, {% tag %} and <% code %> exactly as they are
    - Keep the tone and style of the source
    - Answer with one JSON object that maps each item's number (n) to its #{target_name} text, and nothing else
    """

    items =
      Enum.map(batch, fn {unit, id} ->
        %{"n" => id, "format" => Map.get(unit, :format, "plain"), "source" => unit.source}
        |> put_translation(unit)
        |> put_previous_source(unit)
      end)

    {system_prompt, Jason.encode!(%{"items" => items})}
  end

  defp put_translation(%{} = item, %{kind: "review", current: current}) when is_binary(current),
    do: Map.put(item, "translation", current)

  defp put_translation(item, _unit), do: item

  defp put_previous_source(item, unit) do
    case previous_source(unit) do
      nil -> item
      previous -> Map.put(item, "previous_source", previous)
    end
  end

  defp previous_source(%{kind: "review", source_previous: previous}) when is_binary(previous), do: previous
  defp previous_source(_unit), do: nil

  # The reply's JSON object, also inside a code fence or after a preamble
  defp parse(text) do
    with [json] <- Regex.run(~r/\{.*\}/s, text),
         {:ok, %{} = replies} <- Jason.decode(json) do
      {:ok, Map.new(replies, fn {id, value} -> {to_string(id), value} end)}
    else
      _ -> {:error, :invalid_response}
    end
  end
end
