defmodule BrandoAdmin.LoginBehindProxyTest do
  # Changes the trusted proxies, an application setting, so runs alone.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Users.SecurityEvent
  alias Brando.Users.Throttle
  alias Brando.Users.UserConfig

  setup do
    put_test_env(:trusted_proxies, ["10.77.0.0/16"])
    Throttle.reset()
    on_exit(&Throttle.reset/0)

    user =
      Factory.insert(:random_user, role: :editor, config: %UserConfig{reset_password_on_first_login: false})

    {:ok, user: user}
  end

  defp through(proxy, client) do
    %{Phoenix.ConnTest.build_conn() | remote_ip: proxy}
    |> Plug.Conn.put_req_header("x-forwarded-for", client)
  end

  defp junk(conn),
    do:
      post(conn, "/admin/login", %{"user" => %{"email" => "x#{System.unique_integer()}@example.test", "password" => "x"}})

  test "behind a trusted proxy, each visitor has their own limit", %{user: user} do
    proxy = {10, 77, 0, 1}
    for n <- 1..Throttle.config()[:login_per_ip], do: junk(through(proxy, "198.51.100.#{rem(n, 3) + 1}"))

    # Another visitor, through the same proxy, logs in
    conn =
      post(through(proxy, "203.0.113.50"), "/admin/login", %{"user" => %{"email" => user.email, "password" => "admin"}})

    assert redirected_to(conn) == "/admin"

    # and the log has their own address
    assert [%{ip: "203.0.113.50"}] =
             Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :login)
  end

  test "behind an untrusted proxy, the header is ignored and everyone shares its limit", %{user: user} do
    proxy = {192, 168, 50, 1}
    for n <- 1..Throttle.config()[:login_per_ip], do: junk(through(proxy, "198.51.100.#{n}"))

    conn =
      post(through(proxy, "203.0.113.50"), "/admin/login", %{"user" => %{"email" => user.email, "password" => "admin"}})

    assert redirected_to(conn) == "/admin/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
  end
end
