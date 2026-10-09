defmodule Brando.Blueprint.Forms.WriteWithAI do
  @moduledoc """
  `write_with_ai:` on a `:rich_text` input: Write with AI in its toolbar.

  It is on whenever `Brando.AI` is configured. `false` turns it off; a keyword
  list gives its requests instructions, the fields they read and a model:

      input :body, :rich_text,
        write_with_ai: [prompt: "Keep the magazine's plain tone.", from: [:title], model: :fast]

  * `prompt`: instructions every request starts with.
  * `from`: fields whose values follow the instructions, as an AI action's
    `from:` (`Brando.Blueprint.Forms.AIAction`).
  * `model`: a `"provider:model"` spec or a name from the `models:` config.

  The deprecated `ai:` on a `:rich_text` input meant the same and is read as
  `write_with_ai:` (`from_ai/1`); it also keeps the request options `ai:`
  took (`api_key`, `temperature`, …).
  """
  alias Brando.Blueprint.Forms.AIAction

  @schema [
    prompt: [type: :string, doc: "Instructions every request starts with."],
    from: [type: {:wrap_list, :atom}, doc: "The fields whose values follow the instructions."],
    model: [type: {:or, [:atom, :string]}, doc: "A `\"provider:model\"` spec or a name from the `models:` config."]
  ]

  @doc """
  Checks an input's `write_with_ai:` when the Blueprint compiles: `nil`,
  `true`, `false` or the options above, on a `:rich_text` input.
  """
  @spec validate(term(), term()) :: {:ok, term()} | {:error, String.t()}
  def validate(_type, nil), do: {:ok, nil}
  def validate(:rich_text, value) when is_boolean(value), do: {:ok, value}

  def validate(:rich_text, opts) when is_list(opts) do
    case Spark.Options.validate(opts, @schema) do
      {:ok, opts} -> {:ok, opts}
      {:error, error} -> {:error, "write_with_ai: " <> Exception.message(error)}
    end
  end

  def validate(:rich_text, value),
    do: {:error, "write_with_ai must be true, false or a keyword list of options, got: #{inspect(value)}"}

  def validate(type, _value), do: {:error, "write_with_ai works on :rich_text inputs, not #{inspect(type)}"}

  @doc """
  The `write_with_ai:` options the deprecated `ai:` on a `:rich_text` input
  stands for: its `prompt`, `context:` as `from`, `model` and request options.
  """
  @spec from_ai(term()) :: keyword()
  def from_ai(ai_opts) do
    opts = AIAction.keyword(ai_opts)

    [
      prompt: opts[:prompt],
      from: AIAction.context_fields(opts[:context]),
      model: opts[:model]
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Kernel.++(Keyword.take(opts, AIAction.request_opt_keys()))
  end

  @doc "The `write_with_ai:` to write for `opts` (`from_ai/1`), as Blueprint source."
  @spec to_source(keyword()) :: String.t()
  def to_source(opts) do
    options =
      opts
      |> Keyword.take([:prompt, :from, :model])
      |> Enum.map_join(",\n", fn {key, value} -> "  #{key}: #{inspect(value, printable_limit: :infinity)}" end)

    "write_with_ai: [\n#{options}\n]"
  end
end
