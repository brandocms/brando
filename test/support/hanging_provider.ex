defmodule Brando.Test.HangingProvider do
  @moduledoc """
  A video provider that hangs, on a local port, for the provider clients'
  timeouts (#3457). Route a provider's requests to it with

      req_options: [adapter: Brando.Test.HangingProvider, retry: false]

  and `route/1` in the process that makes the requests. They go through
  Req's own Finch adapter, so the connect, the wait for an answer and their
  timeouts are real. Each request sends `{:hanging_provider, method, path}`
  to that process first.
  """

  @doc """
  A port whose accept queue is full: the kernel drops each new connect's
  SYN, so the connect hangs, as one to a host behind a firewall that drops
  its packets does. The sockets are the calling process's, and close when
  it exits.
  """
  @spec unanswered_connect() :: :inet.port_number()
  def unanswered_connect do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, backlog: 0, active: false)
    {:ok, port} = :inet.port(listen)
    fill_accept_queue(port, 10)
    port
  end

  defp fill_accept_queue(_port, 0), do: raise("could not fill the accept queue of a local port")

  defp fill_accept_queue(port, tries) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [active: false], 100) do
      {:ok, _socket} -> fill_accept_queue(port, tries - 1)
      {:error, :timeout} -> :ok
    end
  end

  @doc """
  A port that accepts each connection and never answers on it. Served by a
  process linked to the caller.
  """
  @spec silent() :: :inet.port_number()
  def silent do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    {:ok, port} = :inet.port(listen)
    pid = spawn_link(fn -> accept_forever(listen, []) end)
    :ok = :gen_tcp.controlling_process(listen, pid)
    port
  end

  defp accept_forever(listen, held) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} -> accept_forever(listen, [socket | held])
      {:error, _reason} -> :ok
    end
  end

  @doc "Routes the calling process's provider requests to `port`."
  @spec route(:inet.port_number()) :: :ok
  def route(port) do
    Process.put(__MODULE__, {port, self()})
    :ok
  end

  @doc false
  def run(request) do
    {port, test} = Process.get(__MODULE__) || raise "no port routed to, see route/1"
    send(test, {:hanging_provider, request.method |> to_string() |> String.upcase(), request.url.path})
    Req.Finch.run(%{request | url: %{request.url | scheme: "http", host: "127.0.0.1", port: port}})
  end
end
