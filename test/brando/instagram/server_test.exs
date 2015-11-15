defmodule Brando.InstagramServerTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, server} = Brando.Instagram.Server.start_link
    {:ok, server: server}
  end

  test "init", %{server: server} do
    {:ok, {{:interval, pid}, _, fetch}} = Brando.Instagram.Server.init(server)
    assert is_reference(pid)
    assert fetch == {:user, "dummy_user"}
    assert_receive :poll
  end

  test "stop", %{server: server} do
    assert Brando.Instagram.Server.stop(server) == :ok
  end
end
