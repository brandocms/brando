defmodule Brando.InstagramServerTest do
  use ExUnit.Case, async: false

  setup do
    server = case Brando.Instagram.Server.start_link do
      {:ok, server} -> server
      {:error, {:already_started, server}} -> server
    end
    {:ok, server: server}
  end

  test "init", %{server: server} do
    {:ok, {{:interval, pid}, _, fetch}} = Brando.Instagram.Server.init(server)
    assert is_reference(pid)
    assert fetch in [{:user, "dummy_user"}, {:tags, ["haraball"]}]
    assert_receive :poll
  end

  test "stop", %{server: server} do
    assert Brando.Instagram.Server.stop(server) == :ok
  end
end
