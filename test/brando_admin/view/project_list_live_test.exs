# defmodule BrandoAdmin.ListViewTest do
#   use Brando.ConnCase
#   import Phoenix.LiveViewTest
#   import Plug.Conn
#   import RouterHelper
#   alias Brando.Factory
#   @endpoint BrandoIntegrationWeb.Endpoint

#   setup %{conn: conn} do
#     ExMachina.Sequence.reset()
#     current_user = Factory.insert(:user)

#     conn =
#       conn
#       |> with_session()
#       |> BrandoAdmin.UserAuth.log_in_user(current_user)

#     # |> recycle()

#     {:ok, conn: conn, current_user: current_user}
#   end

#   test "project list", %{conn: conn} do
#     {:ok, view, html} = live(conn, "/admin/projects")
#     html = view |> element("#user-13 a", "Delete") |> render_click()
#     refute html =~ "user-13"
#     refute view |> element("#user-13") |> has_element?()
#   end
# end
