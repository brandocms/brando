defmodule BrandoAdmin.PasswordResetLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]
  import Swoosh.TestAssertions

  alias Brando.Users
  alias Brando.Users.UserConfig

  defp sent_token do
    assert_email_sent(fn email ->
      [_, token] = Regex.run(~r{/admin/reset-password/([A-Za-z0-9_-]+)}, email.text_body)
      send(self(), {:token, token})
    end)

    assert_received {:token, token}
    token
  end

  defp anonymous, do: Phoenix.ConnTest.build_conn()

  describe "forgot password" do
    test "the login page links to it" do
      {:ok, view, _html} = live(anonymous(), "/admin/login")
      assert has_element?(view, ~s(a[href="/admin/reset-password"]), "Forgot password?")
    end

    test "answers the same whether or not the account exists" do
      user = Factory.insert(:random_user, config: %UserConfig{})

      replies =
        for email <- [user.email, "nobody@example.com"] do
          {:ok, view, _html} = live(anonymous(), "/admin/reset-password")
          html = view |> form("#reset_password_form", user: %{email: email}) |> render_submit()

          html
          |> Floki.parse_document!()
          |> Floki.find("#reset_password_sent .alert")
          |> Floki.text()
          |> String.replace(email, "")
        end

      assert [same, same] = replies
      assert same =~ "we have sent it a link"
      assert sent_token()
      assert_no_email_sent()
    end
  end

  describe "choosing a new password" do
    setup do
      user = Factory.insert(:random_user, config: %UserConfig{})
      :ok = Users.request_password_reset(user.email)
      {:ok, user: user, token: sent_token()}
    end

    test "sets it, logs the user out everywhere and uses up the link", %{user: user, token: token} do
      session = Users.generate_user_session_token(user)
      {:ok, view, _html} = live(anonymous(), "/admin/reset-password/#{token}")

      html =
        view
        |> form("#new_password_form", user: %{password: "new password", password_confirmation: "other"})
        |> render_submit()

      assert html =~ "does not match"

      view
      |> form("#new_password_form", user: %{password: "new password", password_confirmation: "new password"})
      |> render_submit()

      assert %{"info" => "Your password has been changed" <> _} = assert_redirect(view, "/admin/login")
      assert is_nil(Users.get_user_by_session_token(session))

      conn = post(anonymous(), "/admin/login", %{"user" => %{"email" => user.email, "password" => "new password"}})
      assert redirected_to(conn) == "/admin"

      assert {:ok, _view, html} =
               anonymous() |> live("/admin/reset-password/#{token}") |> follow_redirect(anonymous())

      assert html =~ "invalid or has expired"
    end

    test "an unknown link is sent back to ask for a new one" do
      assert {:error, {:live_redirect, %{to: "/admin/reset-password"}}} =
               live(anonymous(), "/admin/reset-password/nonsense")
    end
  end

  describe "changing the password while logged in" do
    test "needs the current password and keeps this session", %{conn: conn, current_user: user} do
      other = Users.generate_user_session_token(user)
      {:ok, view, _html} = live(conn, "/admin/users/password")

      # The session is kept by its token row id; the token stays out of state
      assigns = :sys.get_state(view.pid).socket.assigns
      refute Map.has_key?(assigns, :session_token)
      assert assigns.session_id == Users.token_id(get_session(conn, :user_token))

      html =
        view
        |> form("#password_form",
          user: %{current_password: "wrong", password: "new password", password_confirmation: "new password"}
        )
        |> render_submit()

      assert html =~ "is not your current password"

      view
      |> form("#password_form",
        user: %{current_password: "admin", password: "new password", password_confirmation: "new password"}
      )
      |> render_submit()

      assert_redirect(view, "/admin")
      assert is_nil(Users.get_user_by_session_token(other))
      assert Users.get_user_by_session_token(get_session(conn, :user_token)).id == user.id
    end

    test "is where the first login goes" do
      user = Factory.insert(:random_user, config: %UserConfig{reset_password_on_first_login: true})

      conn = post(anonymous(), "/admin/login", %{"user" => %{"email" => user.email, "password" => "admin"}})
      assert redirected_to(conn) == "/admin/users/password"

      {:ok, _view, html} = live(log_in_user(anonymous(), user), "/admin/users/password")
      assert html =~ "Set your password"
    end
  end

  describe "the user form" do
    test "a superuser sends another user a reset link", %{conn: conn} do
      other = Factory.insert(:random_user, config: %UserConfig{}, avatar: nil)
      {view, html} = live_form(conn, "/admin/users/update/#{other.id}", "user_form")

      refute html =~ ~s(name="user[password]")
      view |> element("[data-testid=send-password-reset]") |> render_click()

      assert_email_sent(fn email ->
        assert email.to == [{"", other.email}]
        assert email.text_body =~ "An administrator sent you this link"
      end)
    end

    test "a superuser can set a password instead, and the user must replace it", %{conn: conn} do
      other = Factory.insert(:random_user, config: %UserConfig{reset_password_on_first_login: false}, avatar: nil)
      session = Users.generate_user_session_token(other)
      {view, _html} = live_form(conn, "/admin/users/update/#{other.id}", "user_form")

      view |> element("[data-testid=open-set-password]") |> render_click()
      assert has_element?(view, "#user-set-password-form")

      html =
        view
        |> form("#user-set-password-form", set_password: %{password: "set by admin", password_confirmation: "other"})
        |> render_submit()

      assert html =~ "does not match"

      view
      |> form("#user-set-password-form",
        set_password: %{password: "set by admin", password_confirmation: "set by admin"}
      )
      |> render_submit()

      assert_redirect(view, "/admin/users/update/#{other.id}")
      assert is_nil(Users.get_user_by_session_token(session))
      assert_email_sent(subject: "Your password was changed")

      conn = post(anonymous(), "/admin/login", %{"user" => %{"email" => other.email, "password" => "set by admin"}})
      assert redirected_to(conn) == "/admin/users/password"
    end

    test "your own form links to changing your password", %{conn: conn, current_user: user} do
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [avatar_id: nil])
      {view, _html} = live_form(conn, "/admin/users/update/#{user.id}", "user_form")
      assert has_element?(view, ~s(a[href="/admin/users/password"]))
      refute has_element?(view, "[data-testid=send-password-reset]")
      refute has_element?(view, "[data-testid=open-set-password]")
      render_click(view, "open_set_password", %{})
      refute has_element?(view, "#user-set-password-form")
    end
  end
end
