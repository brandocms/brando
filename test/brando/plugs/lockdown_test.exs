defmodule Brando.Plug.LockdownTest do
  # Not `async: true`: every test here mutates `:brando, :lockdown` and
  # `:lockdown_until`, which are global application env. `put_test_env/2`
  # restores them, but a restore is not isolation — nothing else reads those
  # keys today, and the first test that does would inherit a flake that reads
  # as a bug in itself.
  use ExUnit.Case, async: false
  use RouterHelper

  import Brando.Test.Support, only: [put_test_env: 2]
  import Plug.Conn

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
    put_test_env(:lockdown, true)

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == 302
    assert List.keyfind(conn.resp_headers, "location", 0) == {"location", "/coming-soon"}

    # A mid-test toggle, not a teardown — the off branch is the other half of
    # what this test asserts. `put_test_env/2` above still deletes the key on
    # exit, which is what these tests used to get wrong: they "restored"
    # `:lockdown` to `false` and `:lockdown_until` to `nil`, neither of which is
    # the absent key they started from, and both only if no assertion failed
    # first.
    Application.put_env(:brando, :lockdown, false)

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == nil
  end

  test "lockdown with auth" do
    put_test_env(:lockdown, true)

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
  end

  test "lockdown pass with lockdown_authorized" do
    put_test_env(:lockdown, true)
    put_test_env(:lockdown_password, "my_pass")

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
  end

  test "lockdown pass with expired target date" do
    put_test_env(:lockdown, true)
    put_test_env(:lockdown_until, ~U[2015-01-13 10:00:00Z])

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == nil
  end

  test "lockdown pass with future target date" do
    put_test_env(:lockdown, true)
    put_test_env(:lockdown_until, ~U[2060-01-13 10:00:00Z])

    conn =
      :get
      |> call("/")
      |> LockdownPlug.call([])

    assert conn.status == 302
  end
end
