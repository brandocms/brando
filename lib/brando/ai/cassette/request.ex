defmodule Brando.AI.Cassette.Request do
  @moduledoc """
  The normalised form of a model request, as a cassette records and matches it.

  A request is reduced to a JSON-friendly map:

      %{
        "kind" => "generate" | "stream",
        "model" => "openai:gpt-4o-mini",
        "system" => "You write alt text…" | nil,
        "messages" => [%{"role" => "user", "content" => "…"}, …],
        "tools" => [%{"name" => "search_entries", "digest" => "3f2a…"}],
        "params" => %{"max_tokens" => 4096, "temperature" => 0.4}
      }

  What changes from run to run is left out or replaced, so the same flow
  matches the same recording:

    * tool call ids and tool result ids are dropped;
    * text that is JSON (tool results, tool arguments) is decoded, and the
      values of `id`, `uid`, `ids`, `*_id`, `*_uid`, `*_ids` and `*_at` keys
      become `"<id>"` or `"<timestamp>"`;
    * the values of the cassette's `ignore_keys:` become `"<ignored>"`;
    * UUIDs and ISO 8601 timestamps in text become `"<uuid>"` and `"<timestamp>"`;
    * binary images become their media type, size and a SHA-256 digest;
    * a tool becomes its name and a digest of its description and parameters;
    * only model parameters are kept: no API key, HTTP options or callbacks.

  Values given as cassette `bindings:` are replaced by `"{{name}}"`, so a
  recording made against one database matches a run against another.
  """

  alias ReqLLM.Message.ContentPart

  @params ~w(temperature max_tokens top_p top_k presence_penalty frequency_penalty tool_choice stop seed
             reasoning_effort response_format)a

  @uuid ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i
  @timestamp ~r/\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?\b/

  @doc """
  Normalise a `generate_text/3` or `stream_text/3` call. `kind` is
  `:generate` or `:stream`; `bindings` is a map of names to values.
  """
  @spec normalize(atom(), term(), term(), keyword(), map(), [String.t()]) :: map()
  def normalize(kind, model, prompt, opts, bindings \\ %{}, ignore_keys \\ []) do
    context = context(prompt, opts)
    {system, messages} = Enum.split_with(context.messages, &(&1.role == :system))

    %{
      "kind" => to_string(kind),
      "model" => model_spec(model),
      "system" => system_text(system),
      "messages" => Enum.map(messages, &message/1),
      "tools" => tools(opts[:tools] || context.tools || []),
      "params" => params(opts)
    }
    |> ignore(Enum.map(ignore_keys, &to_string/1))
    |> bind(bindings)
  end

  @doc "Replace the values of `keys`, wherever they appear, with `\"<ignored>\"`."
  @spec ignore(term(), [String.t()]) :: term()
  def ignore(term, []), do: term

  def ignore(map, keys) when is_map(map),
    do: Map.new(map, fn {key, value} -> if key in keys, do: {key, "<ignored>"}, else: {key, ignore(value, keys)} end)

  def ignore(list, keys) when is_list(list), do: Enum.map(list, &ignore(&1, keys))
  def ignore(other, _keys), do: other

  @doc "The `\"provider:model\"` spec of a model given as a string, an `LLMDB.Model` or a tuple."
  @spec model_spec(term()) :: String.t()
  def model_spec(spec) when is_binary(spec), do: spec
  def model_spec(%{provider: provider, id: id}), do: "#{provider}:#{id}"
  def model_spec({provider, id, _opts}) when is_binary(id), do: "#{provider}:#{id}"
  def model_spec({provider, opts}) when is_list(opts), do: "#{provider}:#{opts[:id] || opts[:model]}"
  def model_spec(other), do: inspect(other)

  defp context(prompt, opts) do
    case ReqLLM.Context.normalize(prompt, system_prompt: opts[:system_prompt], validate: false) do
      {:ok, context} -> context
      {:error, _} -> %ReqLLM.Context{messages: [ReqLLM.Context.user(inspect(prompt))]}
    end
  end

  defp system_text([]), do: nil
  defp system_text(messages), do: Enum.map_join(messages, "\n\n", &(&1.content |> parts() |> text_of())) |> scrub()

  defp text_of(parts) when is_binary(parts), do: parts
  defp text_of(parts), do: Enum.map_join(parts, "\n", &(&1["text"] || ""))

  defp message(%ReqLLM.Message{role: :tool} = message) do
    %{"role" => "tool", "name" => message.name, "content" => message.content |> parts() |> decode_parts()}
  end

  defp message(%ReqLLM.Message{} = message) do
    base = %{"role" => to_string(message.role), "content" => message.content |> parts() |> decode_parts()}

    case message.tool_calls do
      [_ | _] = calls -> Map.put(base, "tool_calls", Enum.map(calls, &tool_call/1))
      _ -> base
    end
  end

  defp tool_call(call) do
    %{name: name, arguments: arguments} = ReqLLM.ToolCall.to_map(call)
    %{"name" => name, "arguments" => volatile(stringify(arguments))}
  end

  # One text part reads best as a plain string.
  defp parts(content) when is_binary(content), do: content
  defp parts(content) when is_list(content), do: Enum.flat_map(content, &part/1)
  defp parts(_), do: []

  defp part(%ContentPart{type: :text, text: text}), do: [%{"type" => "text", "text" => text}]

  defp part(%ContentPart{type: :image, data: data, media_type: type}) when is_binary(data),
    do: [%{"type" => "image", "media_type" => type, "bytes" => byte_size(data), "sha256" => digest(data)}]

  defp part(%ContentPart{type: :image_url, url: url}), do: [%{"type" => "image_url", "url" => url}]

  defp part(%ContentPart{type: :file, data: data} = part) when is_binary(data),
    do: [%{"type" => "file", "media_type" => part.media_type, "filename" => part.filename, "sha256" => digest(data)}]

  defp part(%ContentPart{type: :thinking}), do: []
  defp part(%ContentPart{type: type}), do: [%{"type" => to_string(type)}]
  defp part(other) when is_binary(other), do: [%{"type" => "text", "text" => other}]
  defp part(_), do: []

  defp decode_parts(content) when is_binary(content), do: decode_text(content)
  defp decode_parts([%{"type" => "text", "text" => text}]), do: decode_text(text)

  defp decode_parts(parts) when is_list(parts) do
    Enum.map(parts, fn
      %{"type" => "text", "text" => text} = part -> Map.put(part, "text", decode_text(text))
      part -> part
    end)
  end

  # Tool results and arguments are JSON; decoded, they diff and read better.
  defp decode_text(nil), do: ""

  defp decode_text(text) do
    case String.trim(text) do
      "{" <> _ = json -> decode_json(json, text)
      "[" <> _ = json -> decode_json(json, text)
      _ -> scrub(text)
    end
  end

  defp decode_json(json, text) do
    case Jason.decode(json) do
      {:ok, decoded} -> volatile(decoded)
      {:error, _} -> scrub(text)
    end
  end

  defp tools(tools) do
    tools
    |> Enum.map(fn tool ->
      %{"name" => tool_name(tool), "digest" => tool |> tool_definition() |> canonical() |> digest()}
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp tool_name(%{name: name}), do: name
  defp tool_name(%{"name" => name}), do: name
  defp tool_name(other), do: inspect(other)

  defp tool_definition(%{description: description, parameter_schema: schema}),
    do: %{"description" => description, "parameters" => schema |> json_schema() |> stringify()}

  defp tool_definition(other), do: stringify(other)

  defp json_schema(schema) when is_map(schema), do: schema

  defp json_schema(schema) when is_list(schema) do
    ReqLLM.Schema.to_json(schema)
  rescue
    _ -> inspect(schema)
  end

  defp json_schema(other), do: inspect(other)

  defp params(opts) do
    opts
    |> Keyword.take(@params)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), stringify(value)} end)
  end

  @doc """
  Replace the values of volatile keys — ids, uids and timestamps — in decoded
  JSON, and UUIDs and timestamps in its strings.
  """
  @spec volatile(term()) :: term()
  def volatile(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      key = to_string(key)

      cond do
        is_nil(value) -> {key, nil}
        id_key?(key) and (is_integer(value) or is_binary(value)) -> {key, "<id>"}
        id_key?(key) and is_list(value) -> {key, Enum.map(value, fn _ -> "<id>" end)}
        String.ends_with?(key, "_at") and is_binary(value) -> {key, "<timestamp>"}
        true -> {key, volatile(value)}
      end
    end)
  end

  def volatile(list) when is_list(list), do: Enum.map(list, &volatile/1)
  def volatile(text) when is_binary(text), do: scrub(text)
  def volatile(other), do: other

  defp id_key?(key),
    do: key in ["id", "uid", "ids"] or String.ends_with?(key, ["_id", "_uid", "_ids"])

  defp scrub(text) do
    text
    |> String.replace(@uuid, "<uuid>")
    |> String.replace(@timestamp, "<timestamp>")
  end

  @doc """
  Replace binding values by `"{{name}}"`: a leaf equal to a value, and, for
  string values, any occurrence inside a string.
  """
  @spec bind(term(), map()) :: term()
  def bind(term, bindings) when bindings == %{}, do: term

  def bind(term, bindings) do
    pairs = bindings |> Enum.map(fn {name, value} -> {value, "{{#{name}}}"} end) |> Enum.sort_by(&(-weight(elem(&1, 0))))
    do_bind(term, pairs)
  end

  defp weight(value) when is_binary(value), do: byte_size(value)
  defp weight(_), do: 0

  defp do_bind(map, pairs) when is_map(map), do: Map.new(map, fn {key, value} -> {key, do_bind(value, pairs)} end)
  defp do_bind(list, pairs) when is_list(list), do: Enum.map(list, &do_bind(&1, pairs))

  defp do_bind(value, pairs) do
    case List.keyfind(pairs, value, 0) do
      {_, template} -> template
      nil when is_binary(value) -> Enum.reduce(pairs, value, &replace_in/2)
      nil -> value
    end
  end

  defp replace_in({search, template}, text) when is_binary(search) and byte_size(search) > 1,
    do: String.replace(text, search, template)

  defp replace_in(_pair, text), do: text

  @doc "Turn atoms keys and values into strings, so a term is plain JSON."
  @spec stringify(term()) :: term()
  def stringify(%_{} = struct), do: struct |> Map.from_struct() |> stringify()
  def stringify(map) when is_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  def stringify(list) when is_list(list) do
    if list != [] and Keyword.keyword?(list),
      do: list |> Map.new() |> stringify(),
      else: Enum.map(list, &stringify/1)
  end

  def stringify(value) when is_boolean(value) or is_nil(value), do: value
  def stringify(value) when is_atom(value), do: to_string(value)
  def stringify(value) when is_function(value), do: "<function>"
  def stringify(value) when is_pid(value) or is_reference(value) or is_port(value), do: inspect(value)
  def stringify(value) when is_tuple(value), do: value |> Tuple.to_list() |> stringify()
  def stringify(value), do: value

  @doc "A short SHA-256 digest of binary `data`."
  @spec digest(binary()) :: String.t()
  def digest(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  @doc "A term encoded as JSON with sorted keys, so equal terms give equal text."
  @spec canonical(term()) :: String.t()
  def canonical(term), do: term |> ordered() |> Jason.encode!()

  @doc "Maps as `Jason.OrderedObject`s with sorted keys, for stable JSON."
  @spec ordered(term()) :: term()
  def ordered(map) when is_map(map) and not is_struct(map),
    do:
      map
      |> Enum.sort_by(&to_string(elem(&1, 0)))
      |> Enum.map(fn {k, v} -> {k, ordered(v)} end)
      |> Jason.OrderedObject.new()

  def ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  def ordered(other), do: other
end
