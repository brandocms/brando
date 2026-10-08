defmodule Brando.Blueprint.Forms.AIAction do
  @moduledoc """
  A named AI action declared on a form input with `ai_actions:`: a prompt,
  the fields it reads and its constraints. The admin offers a field's actions
  in a small menu and shows the result as a suggestion that the editor
  accepts, edits or discards. See "AI actions on a field" in
  `guides/blueprint_forms.md`.

      input :summary, :textarea,
        label: t("Summary"),
        ai_actions: [
          summarize: [
            label: t("Summarize the article"),
            prompt: "Summarize the article for a listing.",
            from: [:title, :blocks],
            max: 160
          ]
        ]

  The options are checked when the Blueprint compiles: `build/2` here, as the
  input is built, and the fields named in `from:` in
  `Brando.Blueprint.Forms.Verifier`, once the schema exists.
  """
  defstruct name: nil,
            label: nil,
            prompt: nil,
            from: [],
            max: nil,
            tone: nil,
            language: nil,
            model: nil

  @type t :: %__MODULE__{
          name: atom(),
          label: String.t() | nil,
          prompt: String.t(),
          from: [atom()],
          max: pos_integer() | nil,
          tone: String.t() | nil,
          language: String.t() | atom() | nil,
          model: String.t() | atom() | nil
        }

  @input_types [:text, :textarea, :rich_text]

  @schema [
    prompt: [type: :string, required: true, doc: "The instruction sent to the model."],
    from: [
      type: {:wrap_list, :atom},
      required: true,
      doc: "The fields the action reads. `:blocks` reads the block editor's unsaved content."
    ],
    label: [type: :string, doc: "The menu label, translated through the Blueprint's Gettext domain."],
    max: [type: :pos_integer, doc: "The longest result, in characters."],
    tone: [type: :string, doc: "How the result should read, such as \"plain and friendly\"."],
    language: [type: {:or, [:atom, :string]}, doc: "A language code to write in. Defaults to the entry's language."],
    model: [type: {:or, [:atom, :string]}, doc: "A `\"provider:model\"` spec or a name from the `models:` config."]
  ]

  @doc "The input types that take `ai_actions:`."
  def input_types, do: @input_types

  @doc """
  Builds the actions an input declares in `ai_actions:`, or an error message
  for a Blueprint compile error.
  """
  @spec build(atom() | term(), term()) :: {:ok, [t()]} | {:error, String.t()}
  def build(_type, nil), do: {:ok, []}

  def build(type, actions) do
    cond do
      type not in @input_types ->
        {:error, "ai_actions work on #{Enum.map_join(@input_types, ", ", &inspect/1)} inputs, not #{inspect(type)}"}

      not (is_list(actions) and Keyword.keyword?(actions)) ->
        {:error, "ai_actions must be a keyword list of action name and options, got: #{inspect(actions)}"}

      duplicate = duplicate_name(actions) ->
        {:error, "ai_actions declares the action #{inspect(duplicate)} more than once"}

      true ->
        build_each(actions)
    end
  end

  defp build_each(actions) do
    Enum.reduce_while(actions, {:ok, []}, fn {name, opts}, {:ok, built} ->
      case build_one(name, opts) do
        {:ok, action} -> {:cont, {:ok, built ++ [action]}}
        {:error, message} -> {:halt, {:error, "ai_actions #{inspect(name)}: " <> message}}
      end
    end)
  end

  defp build_one(name, opts) do
    with true <- (is_list(opts) and Keyword.keyword?(opts)) || {:error, "options must be a keyword list"},
         {:ok, opts} <- validate(opts),
         :ok <- present(opts[:prompt], "prompt must not be empty"),
         :ok <- present(opts[:from], "from must name at least one field") do
      {:ok, struct(__MODULE__, Keyword.put(opts, :name, name))}
    end
  end

  defp validate(opts) do
    case Spark.Options.validate(opts, @schema) do
      {:ok, opts} -> {:ok, opts}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp present(value, message) when value in [nil, []], do: {:error, message}
  defp present(value, message) when is_binary(value), do: if(String.trim(value) == "", do: {:error, message}, else: :ok)
  defp present(_value, _message), do: :ok

  defp duplicate_name(actions) do
    actions
    |> Keyword.keys()
    |> Enum.frequencies()
    |> Enum.find_value(fn {name, count} -> count > 1 && name end)
  end
end
