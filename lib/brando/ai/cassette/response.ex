defmodule Brando.AI.Cassette.Response do
  @moduledoc """
  Recorded model replies, in the cassette's JSON form, and back.

  A reply to `generate_text/3`:

      %{
        "text" => "A lighthouse on a rocky shore",
        "tool_calls" => [%{"id" => "call_1", "name" => "search_entries", "arguments" => %{…}}],
        "usage" => %{"input_tokens" => 120, "output_tokens" => 14},
        "finish_reason" => "stop"
      }

  A reply to `stream_text/3` carries its chunks in order instead of `text`
  and `tool_calls`:

      %{"chunks" => [%{"type" => "content", "text" => "A light"}, …], "usage" => …, "finish_reason" => "stop"}

  A failed call is `%{"error" => %{"status" => 429, "message" => "Rate limited"}}`
  and replays as a `ReqLLM.Error.API.Request`.

  `"{{name}}"` in tool arguments and text is filled in from the cassette's
  `bindings:` on replay.
  """

  alias Brando.AI.Cassette.Request
  alias ReqLLM.{Message, StreamChunk, ToolCall}
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.StreamResponse.MetadataHandle

  @usage_keys ~w(input_tokens output_tokens total_tokens cached_tokens cache_read_input_tokens
                 cache_creation_input_tokens reasoning_tokens input_cost output_cost total_cost)

  ## Recording

  @doc "The JSON form of a `ReqLLM.Response`."
  @spec dump(ReqLLM.Response.t()) :: map()
  def dump(%ReqLLM.Response{} = response) do
    %{
      "text" => ReqLLM.Response.text(response),
      "tool_calls" => response |> ReqLLM.Response.tool_calls() |> Enum.map(&dump_tool_call/1),
      "usage" => dump_usage(ReqLLM.Response.usage(response)),
      "finish_reason" => response.finish_reason && to_string(response.finish_reason)
    }
    |> reject_empty()
  end

  @doc "The JSON form of an error a client returned."
  @spec dump_error(term()) :: map()
  def dump_error(error) do
    status = if is_map(error), do: Map.get(error, :status)
    message = if is_exception(error), do: Exception.message(error), else: inspect(error)
    %{"error" => reject_empty(%{"status" => status, "message" => message})}
  end

  @doc "The JSON form of a list of `ReqLLM.StreamChunk`s and the stream's metadata."
  @spec dump_stream([StreamChunk.t()], map()) :: map()
  def dump_stream(chunks, metadata) do
    %{
      "chunks" => Enum.map(chunks, &dump_chunk/1),
      "usage" => dump_usage(metadata[:usage]),
      "finish_reason" => metadata[:finish_reason] && to_string(metadata[:finish_reason])
    }
    |> reject_empty()
  end

  defp dump_tool_call(call) do
    %{id: id, name: name, arguments: arguments} = ToolCall.to_map(call)
    %{"id" => id, "name" => name, "arguments" => Request.stringify(arguments)}
  end

  defp dump_usage(usage) when is_map(usage) do
    usage
    |> Request.stringify()
    |> Map.take(@usage_keys)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp dump_usage(_), do: nil

  defp dump_chunk(%StreamChunk{type: :tool_call} = chunk),
    do: %{"type" => "tool_call", "name" => chunk.name, "arguments" => Request.stringify(chunk.arguments || %{})}

  defp dump_chunk(%StreamChunk{type: :meta} = chunk), do: %{"type" => "meta", "data" => Request.stringify(chunk.metadata)}
  defp dump_chunk(%StreamChunk{type: type, text: text}), do: %{"type" => to_string(type), "text" => text}

  defp reject_empty(map), do: Map.reject(map, fn {_key, value} -> value in [nil, [], ""] end)

  ## Replay

  @doc "A `ReqLLM.Response` for a recorded reply, or the error it recorded."
  @spec load(map(), term(), term(), keyword(), map()) :: {:ok, ReqLLM.Response.t()} | {:error, Exception.t()}
  def load(%{"error" => error}, _model, _prompt, _opts, _bindings), do: {:error, error(error)}

  def load(reply, model, prompt, opts, bindings) do
    reply = fill(reply, bindings)

    calls =
      reply
      |> Map.get("tool_calls", [])
      |> Enum.with_index()
      |> Enum.map(fn {call, i} ->
        ToolCall.new(call["id"] || "call_#{i}", call["name"], Jason.encode!(call["arguments"] || %{}))
      end)

    text = reply["text"]
    content = if text in [nil, ""], do: [], else: [ContentPart.text(text)]
    message = %Message{role: :assistant, content: content, tool_calls: if(calls == [], do: nil, else: calls)}
    context = context(prompt, opts)

    {:ok,
     %ReqLLM.Response{
       id: "cassette-" <> Integer.to_string(System.unique_integer([:positive])),
       model: Request.model_spec(model),
       context: %{context | messages: context.messages ++ [message]},
       message: message,
       usage: load_usage(reply["usage"]),
       finish_reason: finish_reason(reply["finish_reason"], calls)
     }}
  end

  @doc "A `ReqLLM.StreamResponse` that replays recorded chunks."
  @spec load_stream(map(), term(), term(), keyword(), map()) :: {:ok, ReqLLM.StreamResponse.t()} | {:error, Exception.t()}
  def load_stream(%{"error" => error}, _model, _prompt, _opts, _bindings), do: {:error, error(error)}

  def load_stream(reply, model, prompt, opts, bindings) do
    reply = fill(reply, bindings)
    chunks = reply |> Map.get("chunks", []) |> Enum.map(&load_chunk/1)
    metadata = %{usage: load_usage(reply["usage"]), finish_reason: finish_reason(reply["finish_reason"], [])}
    {:ok, handle} = MetadataHandle.start_link(fn -> metadata end)

    {:ok,
     %ReqLLM.StreamResponse{
       stream: Stream.map(chunks, & &1),
       metadata_handle: handle,
       cancel: fn -> :ok end,
       model: stream_model(model),
       context: context(prompt, opts)
     }}
  end

  defp load_chunk(%{"type" => "tool_call"} = chunk), do: StreamChunk.tool_call(chunk["name"], chunk["arguments"] || %{})
  defp load_chunk(%{"type" => "thinking", "text" => text}), do: StreamChunk.thinking(text)
  defp load_chunk(%{"type" => "meta"} = chunk), do: StreamChunk.meta(atomize(chunk["data"] || %{}))
  defp load_chunk(%{"text" => text}), do: StreamChunk.text(text || "")

  defp stream_model(model) when is_binary(model) do
    case ReqLLM.model(model) do
      {:ok, model} -> model
      _ -> model
    end
  rescue
    _ -> model
  end

  defp stream_model(model), do: model

  defp context(prompt, opts) do
    case ReqLLM.Context.normalize(prompt, system_prompt: opts[:system_prompt], validate: false) do
      {:ok, context} -> context
      {:error, _} -> ReqLLM.Context.new()
    end
  end

  defp load_usage(nil), do: nil
  defp load_usage(usage), do: atomize(usage)

  defp atomize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_existing_atom(key), atomize(value)} end)
  end

  defp atomize(other), do: other

  defp to_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp to_existing_atom(key), do: key

  @finish_reasons ~w(stop length tool_calls content_filter error cancelled incomplete unknown)

  defp finish_reason(reason, _calls) when reason in @finish_reasons, do: String.to_existing_atom(reason)
  defp finish_reason(_reason, [_ | _]), do: :tool_calls
  defp finish_reason(_reason, _calls), do: :stop

  defp error(error) do
    ReqLLM.Error.API.Request.exception(reason: error["message"] || "recorded error", status: error["status"])
  end

  @doc """
  Fill `"{{name}}"` templates from `bindings`: a string that is just a
  template takes the bound value as it is, so an integer id stays an integer.
  A name with no binding is left as it is, so Liquid such as `{{ title }}`
  in recorded text is safe.
  """
  @spec fill(term(), map()) :: term()
  def fill(term, bindings) when bindings == %{}, do: term
  def fill(term, bindings) when is_map(term), do: Map.new(term, fn {key, value} -> {key, fill(value, bindings)} end)
  def fill(term, bindings) when is_list(term), do: Enum.map(term, &fill(&1, bindings))

  def fill(term, bindings) when is_binary(term) do
    case Regex.run(~r/^\{\{(\w+)\}\}$/, term) do
      [_, name] -> binding(bindings, name, term)
      nil -> Regex.replace(~r/\{\{(\w+)\}\}/, term, fn whole, name -> to_string(binding(bindings, name, whole)) end)
    end
  end

  def fill(term, _bindings), do: term

  defp binding(bindings, name, default) do
    case Enum.find(bindings, fn {key, _value} -> to_string(key) == name end) do
      {_key, value} -> value
      nil -> default
    end
  end
end
