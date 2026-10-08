defmodule Brando.MCP.Server do
  @moduledoc """
  The MCP messages the endpoint answers, over Streamable HTTP, one JSON-RPC
  request per POST, answered with `application/json` (no SSE: tools need no
  streaming).

  Both eras of the protocol are served:

    * **Modern** (`2026-07-28`): every request carries its version, client
      info and capabilities in `_meta`, and the `MCP-Protocol-Version`,
      `Mcp-Method` and `Mcp-Name` headers mirror the body. A header that is
      missing or disagrees with the body is refused (`HeaderMismatch`); an
      unknown version gets `UnsupportedProtocolVersion` with the supported
      list. `server/discover` describes the server.
    * **Legacy** (`2025-11-25`, `2025-06-18`, `2025-03-26`): `initialize`
      negotiates the version, and later requests name it in the
      `MCP-Protocol-Version` header (none means `2025-03-26`). No session is
      created: the server keeps no state between requests.

  Methods: `initialize`, `server/discover`, `ping`, `tools/list` and
  `tools/call`. Notifications are accepted and need no answer. Batches are
  refused.
  """

  alias Brando.MCP.Tools

  @modern ["2026-07-28"]
  @legacy ["2025-11-25", "2025-06-18", "2025-03-26"]
  @meta_version "io.modelcontextprotocol/protocolVersion"
  @meta_capabilities "io.modelcontextprotocol/clientCapabilities"

  @instructions "Brando's content tools for one site environment: read content types, entries, modules and media, " <>
                  "and prepare proposals. A proposal changes nothing until the person approves it in the Brando admin."

  @doc "The protocol versions served, newest first."
  @spec versions() :: [String.t()]
  def versions, do: @modern ++ @legacy

  @type headers :: %{optional(String.t()) => String.t()}
  @type reply :: {pos_integer(), map() | nil}

  @doc """
  Answers one decoded JSON-RPC `message` with the request's MCP `headers`
  (lowercase names), for the connection `auth` at `tenant`. Returns the HTTP
  status and the JSON body, or nil for 202 without a body.
  """
  @spec handle(term(), headers(), map(), map()) :: reply()
  def handle(%{"jsonrpc" => "2.0", "method" => method} = message, headers, auth, tenant) when is_binary(method) do
    params = if is_map(message["params"]), do: message["params"], else: %{}

    cond do
      not Map.has_key?(message, "id") ->
        {202, nil}

      not valid_id?(message["id"]) ->
        {400, error(nil, -32_600, "The request id must be a string or a number.")}

      modern?(params, headers) ->
        modern(message["id"], method, params, headers, auth, tenant)

      true ->
        legacy(message["id"], method, params, headers, auth, tenant)
    end
  end

  def handle(messages, _headers, _auth, _tenant) when is_list(messages),
    do: {400, error(nil, -32_600, "Batches are not supported. Send one request per POST.")}

  def handle(_message, _headers, _auth, _tenant), do: {400, error(nil, -32_600, "Not a JSON-RPC 2.0 request.")}

  defp valid_id?(id), do: is_binary(id) or is_integer(id)

  # A request is modern when its body or its version header says so.
  defp modern?(params, headers) do
    Map.has_key?(meta(params), @meta_version) or headers["mcp-protocol-version"] in @modern
  end

  defp meta(params), do: if(is_map(params["_meta"]), do: params["_meta"], else: %{})

  ## Modern requests

  defp modern(id, method, params, headers, auth, tenant) do
    version = meta(params)[@meta_version]

    case modern_error(method, params, headers) do
      nil ->
        case dispatch(method, params, auth, tenant, version) do
          {:ok, result} -> {200, result(id, modern_result(result))}
          {:error, :not_found} -> {404, error(id, -32_601, "Method not found: #{method}")}
          {:error, code, message} -> {200, error(id, code, message)}
        end

      {code, message, data} ->
        {400, error(id, code, message, data)}
    end
  end

  # What is wrong with a modern request's `_meta` and headers, if anything:
  # the headers mirror the body and must agree with it.
  defp modern_error(method, params, headers) do
    meta = meta(params)
    version = meta[@meta_version]

    cond do
      not is_binary(version) or not is_map(meta[@meta_capabilities]) ->
        {-32_602, "_meta must carry #{@meta_version} and #{@meta_capabilities}.", nil}

      headers["mcp-protocol-version"] != version ->
        {-32_020, "Header mismatch: MCP-Protocol-Version does not match the request's protocol version.", nil}

      version not in @modern ->
        {-32_022, "Unsupported protocol version", %{"supported" => versions(), "requested" => version}}

      true ->
        header_mismatch(method, params, headers)
    end
  end

  defp header_mismatch(method, _params, %{"mcp-method" => header}) when header != method,
    do: {-32_020, "Header mismatch: Mcp-Method does not match the request's method.", nil}

  defp header_mismatch("tools/call", params, headers) do
    if decode_header(headers["mcp-name"]) != params["name"],
      do: {-32_020, "Header mismatch: Mcp-Name does not match the tool's name.", nil}
  end

  defp header_mismatch(_method, _params, _headers), do: nil

  defp modern_result(result) do
    result
    |> Map.put(:resultType, "complete")
    |> Map.update(:_meta, %{"io.modelcontextprotocol/serverInfo" => server_info()}, fn meta ->
      Map.put(meta, "io.modelcontextprotocol/serverInfo", server_info())
    end)
  end

  # `=?base64?…?=` carries a value that is not plain ASCII.
  defp decode_header("=?base64?" <> rest) do
    with true <- String.ends_with?(rest, "?="),
         {:ok, value} <- rest |> String.trim_trailing("?=") |> Base.decode64() do
      value
    else
      _ -> :invalid
    end
  end

  defp decode_header(value), do: value

  ## Legacy requests

  defp legacy(id, "initialize", params, _headers, _auth, _tenant) do
    requested = params["protocolVersion"]
    version = if requested in @legacy, do: requested, else: hd(@legacy)

    {200,
     result(id, %{
       protocolVersion: version,
       capabilities: %{tools: %{listChanged: false}},
       serverInfo: server_info(),
       instructions: @instructions
     })}
  end

  defp legacy(id, method, params, headers, auth, tenant) do
    version = headers["mcp-protocol-version"] || "2025-03-26"

    if version in @legacy do
      case dispatch(method, params, auth, tenant, version) do
        {:ok, result} -> {200, result(id, result)}
        {:error, :not_found} -> {200, error(id, -32_601, "Method not found: #{method}")}
        {:error, code, message} -> {200, error(id, code, message)}
      end
    else
      {400,
       error(
         id,
         -32_600,
         "Unsupported MCP-Protocol-Version #{inspect(version)}. Supported: #{Enum.join(versions(), ", ")}."
       )}
    end
  end

  ## Methods

  defp dispatch("ping", _params, _auth, _tenant, _version), do: {:ok, %{}}

  defp dispatch("server/discover", _params, _auth, _tenant, _version) do
    {:ok,
     %{
       supportedVersions: versions(),
       capabilities: %{tools: %{listChanged: false}},
       instructions: @instructions
     }}
  end

  defp dispatch("tools/list", _params, _auth, _tenant, _version), do: {:ok, %{tools: Tools.list()}}

  defp dispatch("tools/call", %{"name" => name} = params, auth, tenant, _version) when is_binary(name) do
    arguments = params["arguments"] || %{}

    if is_map(arguments) do
      case Tools.call(name, arguments, auth, tenant) do
        {:ok, result} -> {:ok, result}
        {:error, :unknown} -> {:error, -32_602, "Unknown tool: #{String.slice(name, 0, 100)}"}
      end
    else
      {:error, -32_602, "arguments must be an object."}
    end
  end

  defp dispatch("tools/call", _params, _auth, _tenant, _version), do: {:error, -32_602, "name is required."}
  defp dispatch(_method, _params, _auth, _tenant, _version), do: {:error, :not_found}

  defp server_info, do: %{name: "brando", title: "Brando", version: to_string(Brando.version())}

  defp result(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  @doc false
  def error(id, code, message, data \\ nil) do
    error = %{code: code, message: message}
    error = if data, do: Map.put(error, :data, data), else: error
    message = %{jsonrpc: "2.0", error: error}
    if is_nil(id), do: message, else: Map.put(message, :id, id)
  end
end
