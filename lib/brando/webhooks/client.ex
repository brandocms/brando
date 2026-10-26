defmodule Brando.Webhooks.Client do
  @moduledoc false
  # Posts one webhook delivery. Connects to the address `URLGuard` checked —
  # never resolving the host again — with the host name kept for TLS (SNI and
  # certificate verification) and the Host header. Redirects are not
  # followed: a 3xx is a failed delivery like any other non-2xx. The whole
  # exchange, connecting included, has `@timeout` milliseconds, and only the
  # first `@body_limit` bytes of the response are read.
  #
  # `request/5` sends any request the same way, for other requests to
  # addresses an editor chooses, and `run/1` makes it a Req adapter
  # (Brando.Videos.Metadata).

  alias Mint.HTTP

  @timeout 10_000
  @body_limit 4096

  @type result :: %{
          status: non_neg_integer() | nil,
          body: binary(),
          error: atom() | nil,
          duration_ms: non_neg_integer()
        }

  @doc "How long a delivery may take, in milliseconds."
  def timeout, do: Keyword.get(Brando.config(Brando.Webhooks) || [], :timeout, @timeout)

  @doc "How much of a response body is read and kept."
  def body_limit, do: @body_limit

  @spec post(Brando.Webhooks.URLGuard.target(), [{String.t(), String.t()}], binary()) :: result()
  def post(target, headers, body) do
    target
    |> request("POST", headers, body, [])
    |> Map.delete(:headers)
    |> Map.update!(:body, &valid_text/1)
  end

  @doc """
  Sends a `method` request to `target`, without following redirects. The
  result also has the response's `:headers`, and its body is the bytes read.

  Options: `:timeout` for the whole exchange (default `timeout/0`), and
  `:body_limit`, the bytes read (default `body_limit/0`). With
  `whole_body: true`, a longer body is the error `:body_too_large`.
  """
  @spec request(Brando.Webhooks.URLGuard.target(), String.t(), [{String.t(), String.t()}], binary(), keyword()) ::
          map()
  def request(target, method, headers, body, opts) do
    started = System.monotonic_time(:millisecond)
    deadline = started + Keyword.get(opts, :timeout, timeout())

    limits = %{
      body_limit: Keyword.get(opts, :body_limit, @body_limit),
      whole_body: Keyword.get(opts, :whole_body, false)
    }

    result =
      case connect(target, deadline) do
        {:ok, conn} -> request(conn, target, method, headers, body, deadline, limits)
        {:error, reason} -> %{status: nil, headers: [], body: "", error: reason}
      end

    Map.put(result, :duration_ms, System.monotonic_time(:millisecond) - started)
  end

  @doc """
  A Req adapter: sends the request with `request/5` to the target in the
  request's private `:url_guard_target`, so Req's steps (headers,
  decompression, decoding) still run. Options from the private
  `:client_options`. Set `redirect: false` on the request: a redirect is not
  checked by URLGuard.

      req |> Req.Request.put_private(:url_guard_target, target) |> Req.merge(adapter: Client)
  """
  def run(%Req.Request{} = request) do
    target = Req.Request.get_private(request, :url_guard_target) || raise ArgumentError, "no :url_guard_target"
    opts = Req.Request.get_private(request, :client_options, [])
    method = request.method |> to_string() |> String.upcase()
    headers = for {name, values} <- request.headers, value <- values, do: {name, value}

    case request(target, method, headers, IO.iodata_to_binary(request.body || ""), Keyword.put(opts, :whole_body, true)) do
      %{status: status, headers: headers, body: body, error: nil} ->
        {request, Req.Response.new(status: status, headers: headers, body: body)}

      %{error: reason} ->
        {request, Req.TransportError.exception(reason: reason)}
    end
  end

  defp connect(target, deadline) do
    opts = [
      hostname: target.host,
      mode: :passive,
      protocols: [:http1],
      transport_opts: transport_opts(target, max(remaining(deadline), 1))
    ]

    case HTTP.connect(target.scheme, target.address, target.port, opts) do
      {:ok, conn} -> {:ok, conn}
      {:error, %Mint.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _error} -> {:error, :connection_failed}
    end
  end

  defp transport_opts(%{scheme: :https, host: host}, timeout),
    do: [verify: :verify_peer, server_name_indication: String.to_charlist(host), timeout: timeout]

  defp transport_opts(_target, timeout), do: [timeout: timeout]

  defp request(conn, target, method, headers, body, deadline, limits) do
    headers = if body == "" and method in ["GET", "HEAD"], do: headers, else: content_length(headers, body)

    case HTTP.request(conn, method, target.path, headers, body) do
      {:ok, conn, ref} ->
        state = Map.merge(limits, %{status: nil, headers: [], body: [], size: 0})
        {conn, result} = receive_response(conn, ref, state, deadline)
        HTTP.close(conn)
        result

      {:error, conn, _error} ->
        HTTP.close(conn)
        %{status: nil, headers: [], body: "", error: :connection_failed}
    end
  end

  defp content_length(headers, body), do: [{"content-length", Integer.to_string(byte_size(body))} | headers]

  defp receive_response(conn, ref, state, deadline) do
    case remaining(deadline) do
      0 -> {conn, finish(state, :timeout)}
      wait -> conn |> HTTP.recv(0, wait) |> received(ref, state, deadline)
    end
  end

  defp received({:ok, conn, responses}, ref, state, deadline) do
    case consume(responses, ref, state) do
      {:more, state} -> receive_response(conn, ref, state, deadline)
      {:done, state} -> {conn, finish(state, nil)}
    end
  end

  defp received({:error, conn, %Mint.TransportError{reason: :timeout}, _}, _ref, state, _deadline),
    do: {conn, finish(state, :timeout)}

  # After the status, a webhook's answer is what arrived; a body that must be
  # whole was cut off.
  defp received({:error, conn, _error, _}, _ref, state, _deadline),
    do: {conn, finish(state, if(state.status && not state.whole_body, do: nil, else: :connection_failed))}

  defp consume([], _ref, state), do: {:more, state}
  defp consume([{:status, ref, status} | rest], ref, state), do: consume(rest, ref, %{state | status: status})

  defp consume([{:headers, ref, headers} | rest], ref, state),
    do: consume(rest, ref, %{state | headers: state.headers ++ headers})

  defp consume([{:data, ref, bytes} | rest], ref, state) do
    room = state.body_limit - state.size
    kept = binary_part(bytes, 0, min(room, byte_size(bytes)))
    state = %{state | body: [state.body, kept], size: state.size + byte_size(kept)}

    cond do
      # A body that must be whole and is longer than the limit is refused.
      state.whole_body and byte_size(bytes) > room -> {:done, Map.put(state, :too_large, true)}
      # Enough of the body for the log: stop reading.
      not state.whole_body and state.size >= state.body_limit -> {:done, state}
      true -> consume(rest, ref, state)
    end
  end

  defp consume([{:done, ref} | _rest], ref, state), do: {:done, state}
  defp consume([_other | rest], ref, state), do: consume(rest, ref, state)

  defp finish(%{too_large: true} = state, _error),
    do: %{status: state.status, headers: state.headers, body: "", error: :body_too_large}

  defp finish(state, error) do
    body = IO.iodata_to_binary(state.body)
    error = if is_nil(state.status) and is_nil(error), do: :invalid_response, else: error
    error = if state.status != nil and error == :timeout and not state.whole_body, do: nil, else: error
    %{status: state.status, headers: state.headers, body: body, error: error}
  end

  # A cut may split a UTF-8 character, and a body may be binary or carry
  # control characters (Postgres refuses NUL in text): keep printable text,
  # with tabs and line breaks.
  @doc false
  def valid_text(body) do
    body =
      if String.valid?(body),
        do: body,
        else: body |> String.chunk(:valid) |> Enum.filter(&String.valid?/1) |> Enum.join()

    String.replace(body, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, "")
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
