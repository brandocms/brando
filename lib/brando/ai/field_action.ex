defmodule Brando.AI.FieldAction do
  @moduledoc """
  Runs an AI action declared on a form input (`ai_actions:`, see
  `Brando.Blueprint.Forms.AIAction`): builds its prompt from the action's
  instruction, its constraints and the values of the fields it reads.

  The admin form collects those values from the unsaved form and shows the
  reply as a suggestion; nothing here writes to the entry.
  """

  alias Brando.Blueprint.Forms.AIAction

  @doc """
  The prompt for `action`: its instruction, the constraints it declares, the
  language to write in, and a `Context:` block with `context_values`
  (`{field, text}`, as `Brando.AI.Context` gives them).

  ## Options

    * `:language` — the entry's language code, used unless the action names
      its own. Without either, the reply follows the context's language.
    * `:type` — the input type; `:rich_text` asks for paragraphs separated
      by a blank line.
  """
  @spec prompt(AIAction.t(), [{atom(), String.t()}], keyword()) :: String.t()
  def prompt(%AIAction{} = action, context_values, opts \\ []) do
    language = action.language || opts[:language]

    instructions =
      [
        String.trim(action.prompt),
        language_instruction(language),
        action.tone && "Tone: #{action.tone}.",
        action.max && "Use at most #{action.max} characters.",
        format(opts[:type])
      ]
      |> Enum.reject(&(&1 in [nil, false, ""]))
      |> Enum.join("\n")

    Brando.AI.Context.build_prompt(instructions, context_values)
  end

  defp language_instruction(nil), do: "Write in the language of the context."
  defp language_instruction(language), do: "Write in #{Brando.AI.language_name(language)}."

  defp format(:rich_text),
    do:
      "Return only the text for the field, as plain prose with paragraphs separated by a blank line: no HTML, Markdown, quotes or commentary."

  defp format(_type), do: "Return only the text for the field: no quotes, Markdown or commentary."

  @doc "The `Brando.AI` options for `action`: its model, when it names one."
  @spec ai_opts(AIAction.t()) :: keyword()
  def ai_opts(%AIAction{model: nil}), do: []
  def ai_opts(%AIAction{model: model}), do: [model: model]

  @doc "Whether `action` can run: AI is configured for its model."
  @spec available?(AIAction.t()) :: boolean()
  def available?(%AIAction{} = action), do: Brando.AI.configured?(ai_opts(action))

  @doc """
  A reply as field text: trimmed, without the quotes a model may wrap a short
  answer in.
  """
  @spec clean(String.t()) :: String.t()
  def clean(text) when is_binary(text) do
    text = String.trim(text)

    case Regex.run(~r/\A(["“”«»'])(.*)(["“”«»'])\z/su, text) do
      [_, open, inner, close] when {open, close} in [{"\"", "\""}, {"“", "”"}, {"«", "»"}, {"'", "'"}] ->
        if String.contains?(inner, [open, close]), do: text, else: String.trim(inner)

      _ ->
        text
    end
  end

  @doc """
  Suggested text as the value of an input of `type`: rich text gets one
  escaped paragraph per block of text.
  """
  @spec field_value(String.t(), atom()) :: String.t()
  def field_value(text, :rich_text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map_join(fn paragraph ->
      paragraph =
        paragraph
        |> String.trim()
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()
        |> String.replace("\n", "<br>")

      "<p>#{paragraph}</p>"
    end)
  end

  def field_value(text, _type), do: text
end
