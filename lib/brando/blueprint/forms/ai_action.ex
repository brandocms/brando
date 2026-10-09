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
  the forms verifier, once the schema exists.

  Two other sources give an input the same kind of action, named `:generate`
  (see `generate/2`): the deprecated `ai:` option on an input (`origin: :ai`),
  and a site prompt for a meta field in the Meta drawer (`origin: :site`).
  Those keep the request options `ai:` and site prompts take (`api_key`,
  `temperature`, …) in `request_opts`; `ai_actions:` has none.
  """
  defstruct name: nil,
            label: nil,
            prompt: nil,
            from: [],
            max: nil,
            tone: nil,
            language: nil,
            model: nil,
            origin: :ai_actions,
            request_opts: []

  @type t :: %__MODULE__{
          name: atom(),
          label: String.t() | nil,
          prompt: String.t(),
          from: [atom()],
          max: pos_integer() | nil,
          tone: String.t() | nil,
          language: String.t() | atom() | nil,
          model: String.t() | atom() | nil,
          origin: :ai_actions | :ai | :site,
          request_opts: keyword()
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

  # What `ai:` and site prompts pass on to the model besides `model:`
  # (`Brando.AI`'s request options).
  @request_opt_keys [
    :api_key,
    :temperature,
    :max_tokens,
    :top_p,
    :presence_penalty,
    :frequency_penalty,
    :tool_choice,
    :tools,
    :system_prompt,
    :provider_options,
    :receive_timeout,
    :thinking_timeout
  ]

  @doc "The input types that take `ai_actions:`."
  def input_types, do: @input_types

  @doc """
  The `:generate` action for the options of the deprecated `ai:` on an input
  (`origin: :ai`) or of a site prompt (`origin: :site`, `trait :meta, ai:` or
  `config :brando, Brando.AI, fields:`): its `prompt`, `context:` as the
  fields it reads (`from`), its `model` and its request options. `nil` when
  the options have no prompt.

  A `context:` that names nothing is an empty `from`: the prompt goes to the
  model alone, as it did before.
  """
  @spec generate(keyword() | map() | nil, :ai | :site) :: t() | nil
  def generate(ai_opts, origin) when origin in [:ai, :site] do
    opts = keyword(ai_opts)

    case opts[:prompt] do
      prompt when is_binary(prompt) ->
        if String.trim(prompt) == "" do
          nil
        else
          %__MODULE__{
            name: :generate,
            prompt: prompt,
            from: context_fields(opts[:context]),
            model: opts[:model],
            origin: origin,
            request_opts: Keyword.take(opts, @request_opt_keys)
          }
        end

      _ ->
        nil
    end
  end

  @doc """
  Adds the action an input's deprecated `ai:` options run as (`generate/2`)
  to the actions it declares in `ai_actions:`. Not on an input type without
  text, and not when `ai_actions:` already has a `:generate`; the forms
  verifier warns about `ai:` in each case.
  """
  @spec add_deprecated(atom() | term(), [t()], term()) :: [t()]
  def add_deprecated(_type, actions, nil), do: actions

  def add_deprecated(type, actions, ai_opts) do
    with true <- type in @input_types,
         false <- Enum.any?(actions, &(&1.name == :generate)),
         %__MODULE__{} = action <- generate(ai_opts, :ai) do
      actions ++ [action]
    else
      _ -> actions
    end
  end

  @doc """
  The `ai_actions:` to write for an action `generate/2` built from `ai:`
  options, as Blueprint source, for the deprecation warning.
  """
  @spec to_source(t()) :: String.t()
  def to_source(%__MODULE__{} = action) do
    options =
      [
        {:label, ~s|t("Generate")|},
        {:prompt, inspect(action.prompt, printable_limit: :infinity)},
        action.from != [] && {:from, inspect(action.from)},
        action.model && {:model, inspect(action.model)}
      ]
      |> Enum.filter(& &1)
      |> Enum.map_join(",\n", fn {key, value} -> "    #{key}: #{value}" end)

    "ai_actions: [\n  #{action.name}: [\n#{options}\n  ]\n]"
  end

  @doc "The request options `generate/2` keeps besides `model:`."
  def request_opt_keys, do: @request_opt_keys

  defp keyword(opts) when is_list(opts), do: if(Keyword.keyword?(opts), do: opts, else: [])
  defp keyword(opts) when is_map(opts), do: Enum.flat_map(opts, &keyword_pair/1)
  defp keyword(_opts), do: []

  defp keyword_pair({key, value}) when is_atom(key), do: [{key, value}]

  defp keyword_pair({key, value}) when is_binary(key) do
    [{String.to_existing_atom(key), value}]
  rescue
    ArgumentError -> []
  end

  defp keyword_pair(_pair), do: []

  # `context:` as `Brando.AI.Context.normalize_fields/1` reads it: atoms, and
  # strings that name an existing atom.
  defp context_fields(nil), do: []

  defp context_fields(fields) do
    fields
    |> List.wrap()
    |> Enum.flat_map(fn
      field when is_atom(field) and not is_nil(field) ->
        [field]

      field when is_binary(field) ->
        try do
          [String.to_existing_atom(field)]
        rescue
          ArgumentError -> []
        end

      _ ->
        []
    end)
  end

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
