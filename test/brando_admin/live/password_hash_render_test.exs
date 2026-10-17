defmodule BrandoAdmin.PasswordHashRenderTest do
  # No admin page renders a user's stored password hash, which is the value of
  # `password` in a form built from a saved user.
  use Brando.LiveCase

  import Swoosh.TestAssertions

  alias Brando.Users
  alias Brando.Users.User
  alias Brando.Users.UserConfig
  alias BrandoAdmin.Components.Auth

  defp hash_of(%User{id: id}), do: Repo.get!(User, id).password

  defp refute_hash(html, hash) do
    refute html =~ hash
    refute html =~ "$2b$"
  end

  defp password_values(html, name) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(input[type="password"][name="#{name}"]))
    |> Floki.attribute("value")
  end

  describe "Auth.input" do
    test "a password input renders only what was typed, never the field's value" do
      user = %User{password: Bcrypt.hash_pwd_salt("secret1")}
      form = Phoenix.Component.to_form(Users.password_changeset(user), as: "user")

      html = render_component(&Auth.input/1, field: form[:password], type: "password", label: "Password")
      refute_hash(html, user.password)
      assert password_values(html, "user[password]") == []

      typed = Phoenix.Component.to_form(Users.password_changeset(user, %{"password" => "typed"}), as: "user")
      html = render_component(&Auth.input/1, field: typed[:password], type: "password", label: "Password")
      assert password_values(html, "user[password]") == ["typed"]
    end

    test "other inputs still render the field's value" do
      form = Phoenix.Component.to_form(Ecto.Changeset.change(%User{email: "me@example.com"}), as: "user")
      html = render_component(&Auth.input/1, field: form[:email], type: "email", label: "Email")
      assert html =~ ~s(value="me@example.com")
    end
  end

  describe "changing the password while logged in" do
    test "never renders the hash: on mount, while typing, or after a failed save", %{conn: conn, current_user: user} do
      hash = hash_of(user)
      {:ok, view, html} = live(conn, "/admin/users/password")
      refute_hash(html, hash)
      assert password_values(html, "user[password]") == []

      # Only the current password typed: the new password's param is missing
      html = view |> element("#password_form") |> render_change(%{"user" => %{"current_password" => "admin"}})
      refute_hash(html, hash)

      html =
        view
        |> form("#password_form", user: %{current_password: "admin", password: "short", password_confirmation: "x"})
        |> render_submit()

      refute_hash(html, hash)
      assert password_values(html, "user[password]") == ["short"]
    end

    test "never renders the hash on the first-login page" do
      user = Factory.insert(:random_user, config: %UserConfig{reset_password_on_first_login: true})
      {:ok, _view, html} = live(log_in_user(Phoenix.ConnTest.build_conn(), user), "/admin/users/password")
      assert html =~ "Set your password"
      refute_hash(html, hash_of(user))
    end
  end

  test "the reset link's page never renders the hash" do
    user = Factory.insert(:random_user, config: %UserConfig{})
    :ok = Users.request_password_reset(user.email)

    assert_email_sent(fn email ->
      [_, token] = Regex.run(~r{/admin/reset-password/([A-Za-z0-9_-]+)}, email.text_body)
      send(self(), {:token, token})
    end)

    assert_received {:token, token}

    {:ok, view, html} = live(Phoenix.ConnTest.build_conn(), "/admin/reset-password/#{token}")
    refute_hash(html, hash_of(user))

    html = view |> element("#new_password_form") |> render_change(%{"user" => %{"password_confirmation" => "x"}})
    refute_hash(html, hash_of(user))
  end

  test "the user form and its set-password dialog never render the hash", %{conn: conn} do
    other = Factory.insert(:random_user, config: %UserConfig{}, avatar: nil)
    {view, html} = live_form(conn, "/admin/users/update/#{other.id}", "user_form")
    refute_hash(html, hash_of(other))

    html = view |> element("[data-testid=open-set-password]") |> render_click()
    refute_hash(html, hash_of(other))

    html =
      view
      |> element("#user-set-password-form")
      |> render_change(%{"set_password" => %{"password_confirmation" => "x"}})

    refute_hash(html, hash_of(other))
  end

  test "the security page never renders the hash", %{conn: conn, current_user: user} do
    {:ok, view, html} = live(conn, "/admin/users/security")
    refute_hash(html, hash_of(user))

    html = view |> element("[data-testid=two-factor-setup]") |> render_click()
    refute_hash(html, hash_of(user))
  end
end
