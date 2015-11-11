defmodule Brando.Plug.AuthenticateTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias Brando.Plug.Authenticate

  defmodule AuthPlugFail do
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
    plug Authenticate,
      login_url: "/login"

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end
  end

  defmodule AuthPlugFailsPerms do
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

    plug Authenticate,
      login_url: "/login"

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end

    def put_current_user(conn, _) do
       put_session(conn, :current_user, %{role: 0})
    end
  end

  defmodule AuthPlugSucceeds do
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

    plug Authenticate,
      login_url: "/login"

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end

    def put_current_user(conn, _) do
      put_session(conn, :current_user, %{role: 7})
    end
  end

  test "auth fails" do
    conn =
      :get
      |> conn("/", [])
      |> assign(:secret_key_base, "asdf")
      |> AuthPlugFail.call([])

    assert conn.status == 302
    %{phoenix_flash: errors} = conn.private
    assert errors == %{"error" => "Access denied."}
  end

  test "auth succeeds" do
    conn =
      :get
      |> conn("/", [])
      |> assign(:secret_key_base, "asdf")
      |> AuthPlugSucceeds.call([])

    %{phoenix_flash: errors} = conn.private
    assert errors == %{}
  end

  test "auth fails perms" do
    conn =
      :get
      |> conn("/", [])
      |> assign(:secret_key_base, "asdf")
      |> AuthPlugFailsPerms.call([])
    assert conn.status == 302
    %{phoenix_flash: errors} = conn.private
    assert errors == %{"error" => "Access denied."}
  end
end
