defmodule Brando.InstagramServerTest do
  use ExUnit.Case, async: false

  test "init" do
    {:ok, server} = Brando.Instagram.Server.start_link
    {:ok, %{query: query, timer: {:interval, ref}}} = Brando.Instagram.Server.init(server)
    assert is_reference(ref)
    assert_receive :poll
    assert query in [{:user, "dummy_user"}, {:tags, ["haraball"]}]
    Brando.Instagram.Server.stop(server)
  end

  test "stop" do
    server = case Brando.Instagram.Server.start_link do
      {:ok, pid} -> pid
      {:error, {_, pid}} -> pid
    end

    assert Brando.Instagram.Server.stop(server) == :ok
  end
end
