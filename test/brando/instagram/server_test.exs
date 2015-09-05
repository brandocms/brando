# defmodule Brando.InstagramServerTest do
#   use ExUnit.Case, async: true

#   setup do
#     {:ok, server} = Brando.Instagram.Server.start_link(:insta_test)
#     {:ok, server: server}
#   end

#   test "init", %{server: server} do
#     Brando.Instagram.Server.init(server)
#     assert_receive ""
#   end
# end
