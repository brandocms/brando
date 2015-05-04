#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.Dashboard.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  test "index" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/")
    assert html_response(conn, 200) =~ "Ahoy, Iggy!"
  end
end