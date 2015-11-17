defmodule Brando.InstagramServerTest do
  use ExUnit.Case, async: false

  test "init" do
    {:ok, server} = Brando.Instagram.Server.start_link
    {:ok, {{:interval, pid}, _, fetch}} = Brando.Instagram.Server.init(server)
    assert is_reference(pid)
    assert_receive :poll
    assert fetch in [{:user, "dummy_user"}, {:tags, ["haraball"]}]
    Brando.Instagram.Server.stop(server)
  end

  test "stop" do
    {:ok, server} = Brando.Instagram.Server.start_link
    assert Brando.Instagram.Server.stop(server) == :ok
  end
end
