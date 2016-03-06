defmodule Brando.Users.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  test "index redirects to /login when no :current_user" do
    conn =
      :get
      |> call("/admin/users")
      |> with_session
      |> send_request
    assert redirected_to(conn, 302) =~ "/login"
  end

  test "index with logged in user" do
    conn =
      :get
      |> call("/admin/users")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Index - users"
  end

  test "show" do
    user = Forge.saved_user(TestRepo)
    conn =
      :get
      |> call("/admin/users/#{user.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "James Williamson"
  end

  test "profile" do
    user = Forge.saved_user(TestRepo)
    conn =
      :get
      |> call("/admin/users/profile")
      |> with_user(user)
      |> send_request

    assert html_response(conn, 200) =~ "jamesw"
  end

  test "new" do
    conn =
      :get
      |> call("/admin/users/new")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New user"
  end

  test "edit" do
    user = Forge.saved_user(TestRepo)
    conn =
      :get
      |> call("/admin/users/#{user.id}/edit")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Edit user"
  end

  test "edit profile" do
    user = Forge.saved_user(TestRepo)
    conn =
      :get
      |> call("/admin/users/profile/edit")
      |> with_user(user)
      |> send_request

    assert html_response(conn, 200) =~ "Edit profile"
  end

  test "create (post) w/params" do
    user = Forge.user
    conn =
      :post
      |> call("/admin/users/", %{"user" => Map.delete(user, :__struct__)})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/users"
    assert get_flash(conn, :notice) == "User created"
  end

  test "create (post) w/erroneus params" do
    user = Forge.saved_user(TestRepo)
    conn =
      :post
      |> call("/admin/users/", %{"user" => Map.delete(user, :__struct__)})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New user"
    assert get_flash(conn, :error) == "Errors in form"
  end

  test "update (post) w/params" do
    user = Forge.saved_user(TestRepo)
    user_params =
      user
      |> Map.delete(:__struct__)
      |> Map.delete(:id)

    conn =
      :patch
      |> call("/admin/users/#{user.id}", %{"user" => user_params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/users"
    assert get_flash(conn, :notice) == "User updated"
  end

  test "update (post) w/broken params" do
    user =
      TestRepo
      |> Forge.saved_user
      |> Map.delete(:__struct__)
      |> Map.put(:password, "1")
    conn =
      :patch
      |> call("/admin/users/#{user.id}", %{"user" => user})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Edit user"
    assert get_flash(conn, :error) == "Errors in form"
  end

  test "update profile" do
    user = Forge.saved_user(TestRepo)
    conn =
      :patch
      |> call("/admin/users/profile/edit", %{"user" => Map.delete(user, :__struct__)})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/users/profile"
    assert get_flash(conn, :notice) == "Profile updated"
  end

  test "update profile w/broken params" do
    user =
      TestRepo
      |> Forge.saved_user
      |> Map.delete(:__struct__)
      |> Map.put(:password, "1")
    conn =
      :patch
      |> call("/admin/users/profile/edit", %{"user" => user})
      |> with_user(user)
      |> send_request

    assert html_response(conn, 200) =~ "Edit profile"
    assert get_flash(conn, :error) == "Errors in form"
  end

  test "delete_confirm" do
    user = Forge.saved_user(TestRepo)
    conn =
      :get
      |> call("/admin/users/#{user.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Delete user: James Williamson"
  end

  test "delete" do
    user = Forge.saved_user(TestRepo)
    conn =
      :delete
      |> call("/admin/users/#{user.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/users"
    assert get_flash(conn, :notice) =~ "deleted"
  end
end
