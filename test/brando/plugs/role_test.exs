defmodule Brando.Plug.AuthorizeTest do
  use ExUnit.Case, async: true
  use Plug.Test
  import Brando.Plug.Authorize

  defmodule RolePlugFail do
    import Plug.Conn
    import Phoenix.Controller
    use Plug.Builder

    plug Plug.Session,
      store: :cookie,
      key: "_test",
      signing_salt: "signingsalt",
      encryption_salt: "encsalt"
    plug :fetch_session
    plug :fetch_flash
    plug :put_secret_key_base
    plug :authorize, :superuser

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base, "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end
  end

  defmodule RolePlugFailsPerms do
    import Plug.Conn
    import Phoenix.Controller
    use Plug.Builder

    plug Plug.Session,
      store: :cookie,
      key: "_test",
      signing_salt: "signingsalt",
      encryption_salt: "encsalt"
    plug :fetch_session
    plug :fetch_flash
    plug :put_secret_key_base
    plug :put_current_user
    plug :authorize, :superuser

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base, "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end

    def put_current_user(conn, _) do
      conn |> put_session(:current_user, %{role: []})
    end
  end

  defmodule RolePlugSucceeds do
    import Plug.Conn
    import Phoenix.Controller
    use Plug.Builder

    plug Plug.Session,
      store: :cookie,
      key: "_test",
      signing_salt: "signingsalt",
      encryption_salt: "encsalt"
    plug :fetch_session
    plug :fetch_flash
    plug :put_secret_key_base
    plug :put_current_user
    plug :authorize, :superuser

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base, "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end

    def put_current_user(conn, _) do
      conn |> put_session(:current_user, %{role: [:admin, :superuser]})
    end
  end

  test "role fails" do
    conn = conn(:get, "/", [])
    |> assign(:secret_key_base, "asdf")
    |> RolePlugFail.call([])
    assert conn.status == 403
  end

  test "role succeeds" do
    conn = conn(:get, "/", [])
    |> assign(:secret_key_base, "asdf")
    |> RolePlugSucceeds.call([])
    assert conn.status == nil
  end

  test "role fails perms" do
    conn = conn(:get, "/", [])
    |> assign(:secret_key_base, "asdf")
    |> RolePlugFailsPerms.call([])
    assert conn.status == 403
  end

end