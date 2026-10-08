defmodule Brando.MCP.ClientMetadata do
  @moduledoc """
  OAuth clients identify themselves with a Client ID Metadata Document: their
  `client_id` is an `https` URL, and the JSON document there names the
  client and lists its redirect URIs. This is how Claude (claude.ai, Desktop,
  mobile and Claude Code), ChatGPT and VS Code connect to an MCP server they
  have not met. Brando has no dynamic client registration, so nothing an
  unauthenticated caller sends is stored.

  The document is fetched only for a signed-in person who may connect, when
  the consent screen opens: never for an anonymous request. The fetch goes
  through `Brando.Webhooks.URLGuard` (`https`, public addresses only, the
  checked address connected to with the host name kept for TLS), follows no
  redirects, gives up after five seconds and reads at most 5 KB. A valid
  document is cached for five minutes.

  A document is refused unless it is a JSON object whose `client_id` is the
  URL exactly, with a `client_name`, and `redirect_uris` that are all `https`
  or loopback `http` (`127.0.0.1`, `[::1]` or `localhost`), without
  fragments. Its client must be public: `token_endpoint_auth_method` absent
  or `"none"`, and no client secret.

  The client's name is its own claim. The consent screen shows it with the
  host that published it, and the redirect URI's host.
  """

  alias Brando.Webhooks.URLGuard

  @max_bytes 5_120
  @timeout 5_000
  @cache_ttl :timer.minutes(5)
  @max_name 80

  @type t :: %{
          client_id: String.t(),
          client_name: String.t(),
          client_uri: String.t() | nil,
          redirect_uris: [String.t()],
          host: String.t()
        }

  @doc """
  Checks the shape of `client_id` without fetching it: an `https` URL with a
  host and a path other than `/`, no credentials, query, fragment or dot
  segments, at most 512 bytes.
  """
  @spec valid_client_id?(term()) :: boolean()
  def valid_client_id?(client_id) when is_binary(client_id) and byte_size(client_id) <= 512 do
    case URI.new(client_id) do
      {:ok, %URI{scheme: "https", host: host, path: "/" <> rest = path, userinfo: nil, query: nil, fragment: nil}}
      when is_binary(host) and host != "" and rest != "" ->
        not Enum.any?(String.split(path, "/"), &(&1 in [".", ".."]))

      _ ->
        false
    end
  end

  def valid_client_id?(_client_id), do: false

  @doc """
  The client behind `client_id`: from the cache, or fetched and validated.
  Errors: `:invalid_client_id`, `:unreachable`, `:invalid_document`.
  """
  @spec fetch(String.t()) :: {:ok, t()} | {:error, atom()}
  def fetch(client_id) do
    if valid_client_id?(client_id) do
      case Cachex.get(:cache, {__MODULE__, client_id}) do
        {:ok, %{client_id: ^client_id} = client} -> {:ok, client}
        _ -> fetch_and_cache(client_id)
      end
    else
      {:error, :invalid_client_id}
    end
  end

  defp fetch_and_cache(client_id) do
    with {:ok, body} <- get(client_id),
         {:ok, client} <- parse(client_id, body) do
      Cachex.put(:cache, {__MODULE__, client_id}, client, expire: @cache_ttl)
      {:ok, client}
    end
  end

  @doc false
  # Forgets cached documents, for tests.
  def clear_cache do
    {:ok, keys} = Cachex.keys(:cache)
    for {__MODULE__, _} = key <- keys, do: Cachex.del(:cache, key)
    :ok
  end

  @doc """
  Validates a fetched document `body` for `client_id`. Public for tests and
  for `config :brando, Brando.MCP, client_metadata_fetcher: …`.
  """
  @spec parse(String.t(), binary() | map()) :: {:ok, t()} | {:error, :invalid_document}
  def parse(client_id, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = document} -> parse(client_id, document)
      _ -> {:error, :invalid_document}
    end
  end

  def parse(client_id, %{"client_id" => client_id, "redirect_uris" => [_ | _] = redirect_uris} = document) do
    name = clean_name(document["client_name"])

    cond do
      is_nil(name) -> {:error, :invalid_document}
      length(redirect_uris) > 20 -> {:error, :invalid_document}
      not Enum.all?(redirect_uris, &valid_redirect_uri?/1) -> {:error, :invalid_document}
      document["token_endpoint_auth_method"] not in [nil, "none"] -> {:error, :invalid_document}
      Map.has_key?(document, "client_secret") -> {:error, :invalid_document}
      not includes?(document["grant_types"], "authorization_code") -> {:error, :invalid_document}
      not includes?(document["response_types"], "code") -> {:error, :invalid_document}
      true -> {:ok, client(client_id, name, document, redirect_uris)}
    end
  end

  def parse(_client_id, _document), do: {:error, :invalid_document}

  defp client(client_id, name, document, redirect_uris) do
    %{
      client_id: client_id,
      client_name: name,
      client_uri: if(is_binary(document["client_uri"]), do: String.slice(document["client_uri"], 0, 512)),
      redirect_uris: redirect_uris,
      host: URI.parse(client_id).host
    }
  end

  defp includes?(nil, _value), do: true
  defp includes?(list, value) when is_list(list), do: value in list
  defp includes?(_other, _value), do: false

  # One line of printable text, at most 80 characters
  defp clean_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[\p{C}]+/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_name)
    |> case do
      "" -> nil
      name -> name
    end
  end

  defp clean_name(_name), do: nil

  @loopback_hosts ["127.0.0.1", "[::1]", "::1", "localhost"]

  @doc """
  Whether `uri` may be a redirect URI at all: `https` with a host, or `http`
  to a loopback host (a native app's local server, RFC 8252), without a
  fragment or credentials.
  """
  @spec valid_redirect_uri?(term()) :: boolean()
  def valid_redirect_uri?(uri) when is_binary(uri) and byte_size(uri) <= 1024 do
    case URI.new(uri) do
      {:ok, %URI{scheme: "https", host: host, fragment: nil, userinfo: nil}} when is_binary(host) and host != "" -> true
      {:ok, %URI{scheme: "http", host: host, fragment: nil, userinfo: nil}} -> host in @loopback_hosts
      _ -> false
    end
  end

  def valid_redirect_uri?(_uri), do: false

  @doc "Whether `uri` goes to the user's own computer."
  @spec loopback?(String.t()) :: boolean()
  def loopback?(uri), do: match?(%URI{scheme: "http", host: host} when host in @loopback_hosts, URI.parse(uri))

  @doc """
  Whether `client` may be sent back to `requested`: one of its redirect URIs
  exactly, or, for a loopback `http` URI, the same but on any port (RFC 8252
  section 7.3: a native app picks its port when it starts).
  """
  @spec redirect_allowed?(t(), String.t() | nil) :: boolean()
  def redirect_allowed?(%{redirect_uris: registered}, requested) when is_binary(requested) do
    valid_redirect_uri?(requested) and
      (requested in registered or (loopback?(requested) and Enum.any?(registered, &same_but_port?(&1, requested))))
  end

  def redirect_allowed?(_client, _requested), do: false

  defp same_but_port?(registered, requested) do
    loopback?(registered) and portless(registered) == portless(requested)
  end

  defp portless(uri) do
    parsed = URI.parse(uri)
    {parsed.scheme, parsed.host, parsed.path || "", parsed.query}
  end

  ## Fetching

  defp get(client_id) do
    case Keyword.get(Brando.config(Brando.MCP) || [], :client_metadata_fetcher) do
      {module, function} -> apply(module, function, [client_id])
      nil -> http_get(client_id)
    end
  end

  defp http_get(client_id) do
    with {:ok, target} <- URLGuard.resolve(client_id),
         {:ok, body} <- request(target) do
      {:ok, body}
    else
      _ -> {:error, :unreachable}
    end
  end

  defp request(target) do
    deadline = System.monotonic_time(:millisecond) + @timeout

    opts = [
      hostname: target.host,
      mode: :passive,
      protocols: [:http1],
      transport_opts: transport_opts(target)
    ]

    with {:ok, conn} <- Mint.HTTP.connect(target.scheme, target.address, target.port, opts),
         {:ok, conn, ref} <-
           Mint.HTTP.request(
             conn,
             "GET",
             target.path,
             [
               {"accept", "application/json"},
               {"user-agent", "Brando-MCP"}
             ],
             nil
           ) do
      receive_response(conn, ref, %{status: nil, body: [], size: 0}, deadline)
    else
      _ -> {:error, :unreachable}
    end
  end

  defp transport_opts(%{scheme: :https, host: host}),
    do: [verify: :verify_peer, server_name_indication: String.to_charlist(host), timeout: @timeout]

  defp transport_opts(_target), do: [timeout: @timeout]

  defp receive_response(conn, ref, state, deadline) do
    wait = deadline - System.monotonic_time(:millisecond)

    with true <- wait > 0,
         {:ok, conn, responses} <- Mint.HTTP.recv(conn, 0, wait) do
      received(conn, ref, consume(responses, ref, state), deadline)
    else
      false -> close(conn, {:error, :unreachable})
      {:error, conn, _error, _responses} -> close(conn, {:error, :unreachable})
    end
  end

  defp received(conn, ref, {:more, state}, deadline), do: receive_response(conn, ref, state, deadline)
  defp received(conn, _ref, {:done, %{status: 200} = state}, _), do: close(conn, {:ok, IO.iodata_to_binary(state.body)})
  defp received(conn, _ref, {:done, _state}, _deadline), do: close(conn, {:error, :unreachable})
  defp received(conn, _ref, :too_large, _deadline), do: close(conn, {:error, :invalid_document})

  defp close(conn, result) do
    Mint.HTTP.close(conn)
    result
  end

  defp consume([], _ref, state), do: {:more, state}
  defp consume([{:status, ref, status} | rest], ref, state), do: consume(rest, ref, %{state | status: status})
  defp consume([{:headers, ref, _headers} | rest], ref, state), do: consume(rest, ref, state)

  defp consume([{:data, ref, bytes} | rest], ref, state) do
    size = state.size + byte_size(bytes)
    if size > @max_bytes, do: :too_large, else: consume(rest, ref, %{state | body: [state.body, bytes], size: size})
  end

  defp consume([{:done, ref} | _rest], ref, state), do: {:done, state}
  defp consume([_other | rest], ref, state), do: consume(rest, ref, state)
end
