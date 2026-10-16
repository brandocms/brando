defmodule Brando.Plug.LockdownTest do
  # Not `async: true`: every test here mutates `:brando, :lockdown` and
  # `:lockdown_until`, which are global application env. `put_test_env/2`
  # restores them, but a restore is not isolation — nothing else reads those
  # keys today, and the first test that does would inherit a flake that reads
  # as a bug in itself.
  use Brando.ConnCase, async: false
  use RouterHelper

  import Brando.Test.Support, only: [put_test_env: 2]
  import Plug.Conn

  alias Brando.Factory
  alias Brando.Plug.Lockdown

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

  # A request with the session the admin's sign-in writes, or `session`.
  defp request(path, session) do
    :get
    |> call(path)
    |> Plug.Test.init_test_session(session)
    |> fetch_query_params()
    |> Lockdown.call([])
  end

  defp user_session(role) do
    user = Factory.insert(:random_user, role: role)
    %{user_token: Brando.Users.generate_user_session_token(user)}
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

  test "users signed in to the admin pass, other sessions are locked out" do
    put_test_env(:lockdown, true)

    assert request("/", user_session(:superuser)).status == nil

    for session <- [user_session(:user), %{user_token: "not-a-session-token"}, %{}] do
      conn = request("/", session)
      assert conn.status == 302
      assert List.keyfind(conn.resp_headers, "location", 0) == {"location", "/coming-soon"}
    end
  end

  test "the password as ?key= authorizes the session" do
    put_test_env(:lockdown, true)
    put_test_env(:lockdown_password, "my_pass")

    assert request("/?key=wrong", %{}).status == 302

    conn = request("/?key=my_pass", %{})
    assert conn.status == nil
    assert get_session(conn, :lockdown_authorized)

    assert request("/", %{lockdown_authorized: true}).status == nil
  end

  test "without a password, no key authorizes" do
    put_test_env(:lockdown, true)

    assert request("/?key=", %{}).status == 302
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
