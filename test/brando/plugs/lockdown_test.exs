defmodule Brando.Plug.LockdownTest do
  use ExUnit.Case, async: true
  use Plug.Test
  use RouterHelper

  defmodule LockdownPlug do
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
    plug Brando.Plug.Lockdown, [
           layout: {MyApp.LockdownLayoutView, "lockdown.html"},
           view: {MyApp.LockdownView, "lockdown.html"}]

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end
  end

  defmodule LockdownPlugAuth do
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
    plug Brando.Plug.Lockdown, [
           layout: {MyApp.LockdownLayoutView, "lockdown.html"},
           view: {MyApp.LockdownView, "lockdown.html"}]

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end

    def put_current_user(conn, _) do
      conn |> put_session(:current_user, %{role: [:admin, :superuser]})
    end
  end

  defmodule LockdownPlugAuthFail do
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
    plug Brando.Plug.Lockdown, [
           layout: {MyApp.LockdownLayoutView, "lockdown.html"},
           view: {MyApp.LockdownView, "lockdown.html"}]

    def put_secret_key_base(conn, _) do
      put_in conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
    end

    def put_current_user(conn, _) do
      conn |> put_session(:current_user, %{role: []})
    end
  end

  test "lockdown" do
    Application.put_env(:brando, :lockdown, true)

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == 302
    assert conn.resp_headers["location"] == "/coming-soon"

    Application.put_env(:brando, :lockdown, false)

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == nil
  end

  test "lockdown with auth" do
    Application.put_env(:brando, :lockdown, true)

    conn =
      :get
      |> call("/")
      |> LockdownPlugAuth.call([])

    assert conn.status == nil

    conn =
      :get
      |> call("/")
      |> LockdownPlugAuthFail.call([])

    assert conn.status == 302
    assert conn.resp_headers["location"] == "/coming-soon"

    Application.put_env(:brando, :lockdown, false)
  end
end
