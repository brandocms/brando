defmodule Brando.InstagramServerTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, server} = Brando.Instagram.Server.start_link
    {:ok, server: server}
  end

  test "init", %{server: server} do
    {:ok, {{:interval, pid}, :blank, fetch}} = Brando.Instagram.Server.init(server)
    assert is_reference(pid)
    assert fetch == {:user, "dummy_user"}
    assert_receive :poll
  end
end
