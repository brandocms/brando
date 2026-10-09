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

  @doc """
  The `Brando.AI` options for `action`: its model, when it names one, and the
  request options a deprecated `ai:` or a site prompt gave it.
  """
  @spec ai_opts(AIAction.t()) :: keyword()
  def ai_opts(%AIAction{model: nil, request_opts: opts}), do: opts
  def ai_opts(%AIAction{model: model, request_opts: opts}), do: [{:model, model} | opts]

  # The meta fields the Meta drawer edits, and the input each is there.
  @site_fields [meta_title: :text, meta_description: :textarea]

  @doc """
  The AI actions on `field` of `schema`'s form, its input type and options:
  what the form's input declares (`ai_actions:`, and the deprecated `ai:` as
  `:generate`), and for a meta field in the Meta drawer, the site prompt
  (`trait :meta, ai:` or `config :brando, Brando.AI, fields:`) as
  `:generate`, unless the input has its own.

  The admin offers, runs and accepts the same list.
  """
  @spec for_field(module() | nil, struct() | nil, atom()) :: {[AIAction.t()], atom() | nil, keyword()}
  def for_field(schema, form_blueprint, field) do
    case form_blueprint && Brando.Blueprint.Forms.get_field(field, form_blueprint) do
      %Brando.Blueprint.Forms.Input{actions: actions, type: type, opts: opts} ->
        {with_site_action(actions, schema, field), input_type(type, field), opts || []}

      _ ->
        {with_site_action([], schema, field), @site_fields[field], []}
    end
  end

  # A `:hidden` input for a meta field is edited in the Meta drawer, as a
  # text field or a textarea: a suggestion is written as one.
  defp input_type(type, field) do
    if type in AIAction.input_types(), do: type, else: @site_fields[field]
  end

  @doc """
  Whether an empty read of `action`'s fields stops it. Actions declared in
  `ai_actions:` say so instead of asking the model; the `:generate` of a
  deprecated `ai:` or a site prompt sends its prompt anyway, as `ai:` did.
  """
  @spec needs_inputs?(AIAction.t()) :: boolean()
  def needs_inputs?(%AIAction{origin: :ai_actions, from: [_ | _]}), do: true
  def needs_inputs?(%AIAction{}), do: false

  @doc """
  `actions` with the site prompt's `:generate` for `field`, when it is a meta
  field with a site prompt and `actions` has no `:generate` of its own.
  """
  @spec with_site_action([AIAction.t()], module() | nil, atom()) :: [AIAction.t()]
  def with_site_action(actions, schema, field) do
    with true <- Keyword.has_key?(@site_fields, field),
         false <- Enum.any?(actions, &(&1.name == :generate)),
         %AIAction{} = action <- AIAction.generate(Brando.AI.field_ai_opts(schema, field), :site) do
      actions ++ [action]
    else
      _ -> actions
    end
  end

  @doc "Whether `action` can run: AI is configured for its model."
  @spec available?(AIAction.t()) :: boolean()
  def available?(%AIAction{} = action), do: Brando.AI.configured?(ai_opts(action))

  @doc """
  A reply as text for an input of `type`: trimmed, without the quotes a model
  may wrap a short answer in. A single-line `:text` input gets one line, its
  runs of whitespace and line breaks collapsed to a space.
  """
  @spec clean(String.t(), atom() | nil) :: String.t()
  def clean(text, type \\ nil)

  def clean(text, :text) when is_binary(text) do
    text |> String.replace(~r/\s+/u, " ") |> clean(nil)
  end

  def clean(text, _type) when is_binary(text) do
    text = String.trim(text)

    case Regex.run(~r/\A(["“”«»'])(.*)(["“”«»'])\z/su, text) do
      [_, open, inner, close] when {open, close} in [{"\"", "\""}, {"“", "”"}, {"«", "»"}, {"'", "'"}] ->
        if String.contains?(inner, [open, close]), do: text, else: String.trim(inner)

      _ ->
        text
    end
  end

  @doc """
  Whether replacing the rich text `html` with plain paragraphs loses
  something: formatting, links, headings, lists or footnote markers, anything
  but paragraphs and line breaks.
  """
  @spec formatting_lost?(term()) :: boolean()
  def formatting_lost?(html) when is_binary(html), do: Regex.match?(~r/<(?!\/?(?:p|br)\b)[a-z]/i, html)
  def formatting_lost?(_html), do: false

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

  def field_value(text, :text), do: clean(text, :text)
  def field_value(text, _type), do: text
end
