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

    plug Brando.Plug.Lockdown,
      layout: {MyApp.LockdownLayoutView, "lockdown.html"},
      view: {MyApp.LockdownView, "lockdown.html"}

    def put_secret_key_base(conn, _) do
      put_in(
        conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
      )
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

    plug Brando.Plug.Lockdown,
      layout: {MyApp.LockdownLayoutView, "lockdown.html"},
      view: {MyApp.LockdownView, "lockdown.html"}

    def put_secret_key_base(conn, _) do
      put_in(
        conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
      )
    end

    def put_current_user(conn, _) do
      put_session(conn, :current_user, %{role: :superuser})
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

    plug Brando.Plug.Lockdown,
      layout: {MyApp.LockdownLayoutView, "lockdown.html"},
      view: {MyApp.LockdownView, "lockdown.html"}

    def put_secret_key_base(conn, _) do
      put_in(
        conn.secret_key_base,
        "C590A24F0CCB864E01DD077CFF144EFEAAAB7835775438E414E9847A4EE8035D"
      )
    end

    def put_current_user(conn, _) do
      put_session(conn, :current_user, %{role: :user})
    end
  end

  test "lockdown" do
    Application.put_env(:brando, :lockdown, true)

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == 302
    assert List.keyfind(conn.resp_headers, "location", 0) == {"location", "/coming-soon"}

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

    assert List.keyfind(conn.resp_headers, "location", 0) == {"location", "/coming-soon"}

    Application.put_env(:brando, :lockdown, false)
  end

  test "lockdown pass with lockdown_authorized" do
    Application.put_env(:brando, :lockdown, true)
    Application.put_env(:brando, :lockdown_password, "my_pass")

    conn =
      :get
      |> call("/?key=my_pass")
      |> LockdownPlugAuth.call([])

    assert conn.status == nil

    conn =
      :get
      |> call("/")
      |> LockdownPlugAuth.call([])

    assert conn.status == nil

    Application.put_env(:brando, :lockdown, false)
  end

  test "lockdown pass with expired target date" do
    Application.put_env(:brando, :lockdown, true)
    Application.put_env(:brando, :lockdown_until, ~N[2015-01-13 10:00:00])

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == nil

    Application.put_env(:brando, :lockdown, false)
    Application.put_env(:brando, :lockdown_until, nil)
  end

  test "lockdown pass with future target date" do
    Application.put_env(:brando, :lockdown, true)
    Application.put_env(:brando, :lockdown_until, ~N[2060-01-13 10:00:00])

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == 302

    Application.put_env(:brando, :lockdown, false)
    Application.put_env(:brando, :lockdown_until, nil)
  end
end
