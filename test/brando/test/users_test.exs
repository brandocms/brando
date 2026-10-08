defmodule Brando.Test.UsersTest do
  use Brando.ConnCase, async: false
  use Brando.Test

  import Phoenix.LiveViewTest, only: [live: 2]

  alias Brando.Pages.Page

  describe "legacy roles" do
    test "a user has the role given, a superuser by default" do
      assert %{role: :superuser} = insert_user()
      assert %{role: :editor, name: "Ed"} = insert_user(role: :editor, name: "Ed")
    end

    test "permissions need groups mode" do
      assert_raise ArgumentError, ~r/groups mode/, fn -> insert_user(permissions: ["brando.pages.read"]) end
    end
  end

  describe "groups mode" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      :ok
    end

    test "a user can do exactly what they are granted" do
      user = insert_user(permissions: ["brando.admin.access", "brando.pages.read"])

      assert Brando.Authorization.can?(user, :read, Page)
      refute Brando.Authorization.can?(user, :update, Page)
      assert {:error, :forbidden} = Brando.Pages.create_page(params_for(Page), user)
    end

    test "unknown permission keys are named" do
      assert_raise ArgumentError, ~r/brando.pages.fly/, fn -> insert_user(permissions: ["brando.pages.fly"]) end
    end

    test "logging in adds admin access", %{conn: conn} do
      {conn, user} = log_in_as(conn, permissions: ["brando.pages.read"])

      assert Plug.Conn.get_session(conn, :user_token)
      assert Brando.Authorization.Engine.backend_access?(user)
    end
  end

  test "a logged-in conn reaches the admin", %{conn: conn} do
    {conn, _user} = log_in_as(conn, role: :admin)
    assert {:ok, _view, html} = live(conn, "/admin/pages")
    assert html =~ "Pages"
  end
end
