defmodule Brando.Webhooks.Client do
  @moduledoc false
  # Posts one webhook delivery. Connects to the address `URLGuard` checked —
  # never resolving the host again — with the host name kept for TLS (SNI and
  # certificate verification) and the Host header. Redirects are not
  # followed: a 3xx is a failed delivery like any other non-2xx. The whole
  # exchange, connecting included, has `@timeout` milliseconds, and only the
  # first `@body_limit` bytes of the response are read.

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
    started = System.monotonic_time(:millisecond)
    deadline = started + timeout()

    result =
      case connect(target, deadline) do
        {:ok, conn} -> request(conn, target, headers, body, deadline)
        {:error, reason} -> %{status: nil, body: "", error: reason}
      end

    Map.put(result, :duration_ms, System.monotonic_time(:millisecond) - started)
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

  defp request(conn, target, headers, body, deadline) do
    headers = [{"content-length", Integer.to_string(byte_size(body))} | headers]

    case HTTP.request(conn, "POST", target.path, headers, body) do
      {:ok, conn, ref} ->
        state = %{status: nil, body: [], size: 0}
        {conn, result} = receive_response(conn, ref, state, deadline)
        HTTP.close(conn)
        result

      {:error, conn, _error} ->
        HTTP.close(conn)
        %{status: nil, body: "", error: :connection_failed}
    end
  end

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

  defp received({:error, conn, _error, _}, _ref, state, _deadline),
    do: {conn, finish(state, if(state.status, do: nil, else: :connection_failed))}

  defp consume([], _ref, state), do: {:more, state}
  defp consume([{:status, ref, status} | rest], ref, state), do: consume(rest, ref, %{state | status: status})
  defp consume([{:headers, ref, _headers} | rest], ref, state), do: consume(rest, ref, state)

  defp consume([{:data, ref, bytes} | rest], ref, state) do
    room = @body_limit - state.size
    kept = binary_part(bytes, 0, min(room, byte_size(bytes)))
    state = %{state | body: [state.body, kept], size: state.size + byte_size(kept)}

    # Enough of the body for the log: stop reading.
    if state.size >= @body_limit, do: {:done, state}, else: consume(rest, ref, state)
  end

  defp consume([{:done, ref} | _rest], ref, state), do: {:done, state}
  defp consume([_other | rest], ref, state), do: consume(rest, ref, state)

  defp finish(state, error) do
    body = state.body |> IO.iodata_to_binary() |> valid_text()
    error = if is_nil(state.status) and is_nil(error), do: :invalid_response, else: error
    error = if state.status && error == :timeout, do: nil, else: error
    %{status: state.status, body: body, error: error}
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
