defmodule Brando.WebhookReceiver do
  @moduledoc """
  A fake webhook receiver for tests, like Bypass: a small HTTP/1.1 server on
  a random loopback port. Every request it gets is sent to the test process
  as `{:webhook_request, %{method, path, headers, body}}`, and `respond`
  decides the answer: `{status, body}`, `{status, headers, body}`, or
  `{:sleep, ms}` to answer nothing for that long.

      receiver = Brando.WebhookReceiver.start(fn _request -> {200, "ok"} end)
      url = Brando.WebhookReceiver.url(receiver, "/hook")
  """

  def start(respond \\ fn _request -> {200, "ok"} end) do
    test = self()
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    pid = spawn(fn -> accept(socket, test, respond) end)
    :gen_tcp.controlling_process(socket, pid)
    ExUnit.Callbacks.on_exit(fn -> Process.exit(pid, :kill) end)
    %{port: port, pid: pid}
  end

  def url(%{port: port}, path \\ "/hook"), do: "http://127.0.0.1:#{port}#{path}"

  defp accept(socket, test, respond) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        handler = spawn(fn -> serve(client, test, respond) end)
        :gen_tcp.controlling_process(client, handler)
        send(handler, :go)
        accept(socket, test, respond)

      {:error, _} ->
        :ok
    end
  end

  defp serve(client, test, respond) do
    receive do
      :go -> :ok
    end

    with {:ok, request} <- read_request(client) do
      send(test, {:webhook_request, request})
      reply(client, respond.(request))
    end

    :gen_tcp.close(client)
  end

  defp read_request(client), do: read_head(client, "")

  defp read_head(client, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, rest] ->
        [request_line | header_lines] = String.split(head, "\r\n")
        [method, path, _version] = String.split(request_line, " ")

        headers =
          Map.new(header_lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        length = String.to_integer(Map.get(headers, "content-length", "0"))
        {:ok, body} = read_body(client, rest, length)
        {:ok, %{method: method, path: path, headers: headers, body: body}}

      [_incomplete] ->
        case :gen_tcp.recv(client, 0, 5_000) do
          {:ok, data} -> read_head(client, buffer <> data)
          error -> error
        end
    end
  end

  defp read_body(_client, buffer, length) when byte_size(buffer) >= length, do: {:ok, binary_part(buffer, 0, length)}

  defp read_body(client, buffer, length) do
    case :gen_tcp.recv(client, 0, 5_000) do
      {:ok, data} -> read_body(client, buffer <> data, length)
      error -> error
    end
  end

  defp reply(client, {:sleep, ms}), do: Process.sleep(ms) && :gen_tcp.close(client)
  defp reply(client, {status, body}), do: reply(client, {status, [], body})

  defp reply(client, {status, headers, body}) do
    head =
      Enum.map_join(
        [{"content-length", Integer.to_string(byte_size(body))}, {"connection", "close"} | headers],
        fn {key, value} -> "#{key}: #{value}\r\n" end
      )

    :gen_tcp.send(client, "HTTP/1.1 #{status} Status\r\n#{head}\r\n#{body}")
  end
end

defmodule Brando.WebhookTestResolver do
  @moduledoc """
  DNS for webhook tests (`config :brando, Brando.Webhooks, resolver: ...`):
  `*.example.com` is public, `*.internal.test` private, `pinned.test` is
  loopback, `rebind.test` answers what `rebind/1` set last, anything else is
  not found.
  """

  def resolve(host) do
    host = to_string(host)

    cond do
      host == "example.com" or String.ends_with?(host, ".example.com") -> {:ok, [{93, 184, 216, 34}]}
      String.ends_with?(host, ".internal.test") -> {:ok, [{10, 0, 0, 5}]}
      host == "pinned.test" -> {:ok, [{127, 0, 0, 1}]}
      host == "mixed.test" -> {:ok, [{93, 184, 216, 34}, {192, 168, 1, 1}]}
      host == "rebind.test" -> {:ok, [:persistent_term.get({__MODULE__, :rebind}, {93, 184, 216, 34})]}
      true -> {:error, :nxdomain}
    end
  end

  def rebind(address), do: :persistent_term.put({__MODULE__, :rebind}, address)
end
