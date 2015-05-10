#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.Users.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  test "index redirects to /login when no :current_user" do
    conn =
      call(:get, "/admin/brukere")
      |> with_session
      |> send_request
    assert redirected_to(conn, 302) =~ "/login"
  end

  test "index with logged in user" do
    conn =
      call(:get, "/admin/brukere")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Brukeroversikt"
  end

  test "show" do
    user = Forge.saved_user(TestRepo)
    conn =
      call(:get, "/admin/brukere/#{user.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "James Williamson"
  end

  test "profile" do
    Forge.saved_user(TestRepo)
    conn =
      call(:get, "/admin/brukere/profil")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "iggypop"
  end

  test "new" do
    conn =
      call(:get, "/admin/brukere/ny")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny bruker"
  end

  test "edit" do
    user = Forge.saved_user(TestRepo)
    conn =
      call(:get, "/admin/brukere/#{user.id}/endre")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre bruker"
  end

  test "edit profile" do
    user = Forge.saved_user(TestRepo)
    conn =
      call(:get, "/admin/brukere/profil/endre")
      |> with_user(user)
      |> send_request

    assert html_response(conn, 200) =~ "Endre profil"
  end

  test "create (post) w/params" do
    user = Forge.user
    conn =
      call(:post, "/admin/brukere/", %{"user" => Map.delete(user, :__struct__)})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/brukere"
    assert get_flash(conn, :notice) == "Bruker opprettet."
  end

  test "create (post) w/erroneus params" do
    user = Forge.saved_user(TestRepo)
    conn =
      call(:post, "/admin/brukere/", %{"user" => Map.delete(user, :__struct__)})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny bruker"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (post) w/params" do
    user = Forge.saved_user(TestRepo)
    conn =
      call(:patch, "/admin/brukere/#{user.id}", %{"user" => Map.delete(user, :__struct__)})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/brukere"
    assert get_flash(conn, :notice) == "Bruker oppdatert."
  end

  test "update (post) w/broken params" do
    user =
      Forge.saved_user(TestRepo)
      |> Map.delete(:__struct__)
      |> Map.put(:password, "1")
    conn =
      call(:patch, "/admin/brukere/#{user.id}", %{"user" => user})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre bruker"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update profile" do
    user = Forge.saved_user(TestRepo)
    conn =
      call(:patch, "/admin/brukere/profil/endre", %{"user" => Map.delete(user, :__struct__)})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/brukere/profil"
    assert get_flash(conn, :notice) == "Profil oppdatert."
  end

  test "update profile w/broken params" do
    user =
      Forge.saved_user(TestRepo)
      |> Map.delete(:__struct__)
      |> Map.put(:password, "1")
    conn =
      call(:patch, "/admin/brukere/profil/endre", %{"user" => user})
      |> with_user(user)
      |> send_request

    assert html_response(conn, 200) =~ "Endre profil"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "delete" do
    user = Forge.saved_user(TestRepo)
    conn =
      call(:delete, "/admin/brukere/#{user.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/brukere"
  end
end