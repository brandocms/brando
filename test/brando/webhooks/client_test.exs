defmodule Brando.Webhooks.ClientTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.WebhookReceiver
  alias Brando.Webhooks.Client
  alias Brando.Webhooks.URLGuard

  setup do
    put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})
    receiver = WebhookReceiver.start(fn %{path: "/" <> size} -> {200, String.duplicate("x", String.to_integer(size))} end)
    {:ok, target} = URLGuard.resolve("http://pinned.test:#{receiver.port}/")
    %{target: target}
  end

  defp get(target, path, opts), do: Client.request(%{target | path: path}, "GET", [], "", opts)

  test "a body that must be whole is refused past the limit, and read up to it", %{target: target} do
    assert %{status: 200, body: "xxxxxxxxxx", error: nil} = get(target, "/10", body_limit: 10, whole_body: true)
    assert %{body: "", error: :body_too_large} = get(target, "/11", body_limit: 10, whole_body: true)

    # Otherwise it is cut, as for a webhook's log
    assert %{status: 200, body: "xxxxxxxxxx", error: nil} = get(target, "/11", body_limit: 10)
  end

  test "a body that must be whole is an error when the connection closes before its end" do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)

    server =
      spawn(fn ->
        for _ <- 1..2 do
          {:ok, client} = :gen_tcp.accept(socket)
          {:ok, _request} = :gen_tcp.recv(client, 0, 5_000)
          :gen_tcp.send(client, "HTTP/1.1 200 OK\r\ncontent-length: 100\r\n\r\n" <> String.duplicate("x", 50))
          :gen_tcp.close(client)
        end
      end)

    on_exit(fn -> Process.exit(server, :kill) end)
    {:ok, target} = URLGuard.resolve("http://pinned.test:#{port}/")

    assert %{status: 200, error: :connection_failed} = get(target, "/", whole_body: true)
    # A webhook's answer is what arrived
    assert %{status: 200, error: nil} = Client.post(target, [], "")
  end
end
