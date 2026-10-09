defmodule Brando.Blueprint.Forms.WriteWithAI do
  @moduledoc """
  `write_with_ai:` on a `:rich_text` input: Write with AI in its toolbar.

  It is off unless the input asks for it: every request is a paid call to the
  AI service. `true` turns it on, and a keyword list turns it on with
  instructions for its requests, the fields they read and a model:

      input :body, :rich_text, write_with_ai: true

      input :body, :rich_text,
        write_with_ai: [prompt: "Keep the magazine's plain tone.", from: [:title], model: :fast]

  `false`, or no `write_with_ai:`, leaves it off. It shows only where
  `Brando.AI` is configured for its model.

  * `prompt`: instructions every request starts with.
  * `from`: fields whose values follow the instructions, as an AI action's
    `from:` (`Brando.Blueprint.Forms.AIAction`).
  * `model`: a `"provider:model"` spec or a name from the `models:` config.

  The deprecated `ai:` on a `:rich_text` input meant the same and is read as
  `write_with_ai:` (`from_ai/1`), so it stays on; it also keeps the request
  options `ai:` took (`api_key`, `temperature`, …).
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
      {:ok, opts} ->
        if opts[:from] not in [nil, []] and is_nil(opts[:prompt]),
          do: {:error, "write_with_ai: from: needs a prompt: the fields' values follow its instructions"},
          else: {:ok, opts}

      {:error, error} ->
        {:error, "write_with_ai: " <> Exception.message(error)}
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

  @doc """
  The `write_with_ai:` to write for `opts` (`from_ai/1`), as Blueprint
  source: `write_with_ai: true` when there are no options to carry, since
  Write with AI is off unless an input asks for it. `from` goes only with a
  prompt.
  """
  @spec to_source(keyword()) :: String.t()
  def to_source(opts) do
    opts = if opts[:prompt], do: opts, else: Keyword.delete(opts, :from)

    case Keyword.take(opts, [:prompt, :from, :model]) do
      [] ->
        "write_with_ai: true"

      options ->
        lines =
          Enum.map_join(options, ",\n", fn {key, value} -> "  #{key}: #{inspect(value, printable_limit: :infinity)}" end)

        "write_with_ai: [\n#{lines}\n]"
    end
  end
end
