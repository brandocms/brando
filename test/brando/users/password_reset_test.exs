defmodule Brando.Users.PasswordResetTest do
  use Brando.ConnCase, async: false

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Brando.Exception.ConfigError
  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.UserConfig
  alias Brando.Users.UserToken
  alias BrandoIntegration.Repo

  @endpoint BrandoIntegrationWeb.Endpoint

  setup do
    previous = Map.new([:mailer, :env], &{&1, Application.get_env(:brando, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:brando, key)
        {key, value} -> Application.put_env(:brando, key, value)
      end)
    end)

    {:ok, user: Factory.insert(:random_user, config: %UserConfig{reset_password_on_first_login: true})}
  end

  defp tokens(user, context) do
    Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == ^context)
  end

  # The link in the email, and the token at its end
  defp sent_token do
    assert_email_sent(fn email ->
      [_, token] = Regex.run(~r{/admin/reset-password/([A-Za-z0-9_-]+)}, email.text_body)
      send(self(), {:token, token})
    end)

    assert_received {:token, token}
    token
  end

  describe "asking for a reset link" do
    test "emails the account a link with a single-use token, stored hashed", %{user: user} do
      assert :ok = Users.request_password_reset(" #{user.email} ")

      token = sent_token()
      assert [%UserToken{token: stored, sent_to: sent_to}] = tokens(user, "reset_password")
      assert sent_to == user.email
      refute stored == token
      assert stored == :crypto.hash(:sha256, Base.url_decode64!(token, padding: false))
      assert Users.get_user_by_reset_password_token(token).id == user.id
    end

    test "answers the same for an unknown, inactive or deleted account, and sends nothing" do
      inactive = Factory.insert(:random_user, active: false)
      deleted = Factory.insert(:random_user, deleted_at: DateTime.utc_now())

      for email <- ["nobody@example.com", inactive.email, deleted.email] do
        assert :ok = Users.request_password_reset(email)
      end

      assert_no_email_sent()
      assert Repo.aggregate(from(t in UserToken, where: t.context == "reset_password"), :count) == 0
    end

    test "only the newest link works", %{user: user} do
      :ok = Users.request_password_reset(user.email)
      first = sent_token()
      :ok = Users.request_password_reset(user.email)
      second = sent_token()

      assert is_nil(Users.get_user_by_reset_password_token(first))
      assert Users.get_user_by_reset_password_token(second).id == user.id
    end

    test "without a mailer, development and test are told" do
      Application.delete_env(:brando, :mailer)
      assert_raise ConfigError, fn -> Users.request_password_reset("ada@example.com") end
    end

    test "without a mailer, production says so whether or not the account exists", %{user: user} do
      Application.delete_env(:brando, :mailer)
      Application.put_env(:brando, :env, :prod)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :no_mailer} = Users.request_password_reset(user.email)
        assert {:error, :no_mailer} = Users.request_password_reset("nobody@example.com")
      end)

      assert tokens(user, "reset_password") == []
    end
  end

  describe "a reset link" do
    setup %{user: user} do
      :ok = Users.request_password_reset(user.email)
      {:ok, token: sent_token()}
    end

    test "expires after an hour", %{user: user, token: token} do
      Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -61, :minute)]
      )

      assert is_nil(Users.get_user_by_reset_password_token(token))
    end

    test "stops working when the account is deactivated or its email changes", %{user: user, token: token} do
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [active: false])
      assert is_nil(Users.get_user_by_reset_password_token(token))

      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id),
        set: [active: true, email: "changed@example.com"]
      )

      assert is_nil(Users.get_user_by_reset_password_token(token))
    end

    test "is not mistaken for something else" do
      assert is_nil(Users.get_user_by_reset_password_token("not a token!"))
      assert is_nil(Users.get_user_by_reset_password_token(Base.url_encode64("x", padding: false)))
      assert is_nil(Users.get_user_by_reset_password_token(nil))
    end
  end

  describe "reset_user_password/2" do
    test "sets the password and logs the user out everywhere", %{user: user} do
      session = Users.generate_user_session_token(user)
      @endpoint.subscribe(Users.live_socket_id(session))
      :ok = Users.request_password_reset(user.email)
      token = sent_token()

      assert {:ok, updated} =
               Users.reset_user_password(user, %{
                 "password" => "a new password",
                 "password_confirmation" => "a new password",
                 "email" => "attacker@example.com",
                 "role" => "superuser"
               })

      assert Bcrypt.verify_pass("a new password", updated.password)
      assert updated.email == user.email
      refute updated.config.reset_password_on_first_login
      assert tokens(user, "session") == []
      assert is_nil(Users.get_user_by_reset_password_token(token))
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      assert_email_sent(to: [{"", user.email}], subject: "Your password was changed")
    end

    test "checks the new password and keeps everything when it is not accepted", %{user: user} do
      session = Users.generate_user_session_token(user)

      for attrs <- [
            %{"password" => "short", "password_confirmation" => "short"},
            %{"password" => "a new password", "password_confirmation" => "another one"},
            %{"password" => "a new password"},
            %{"password" => "", "password_confirmation" => ""},
            %{"password" => String.duplicate("å", 40), "password_confirmation" => String.duplicate("å", 40)}
          ] do
        assert {:error, %Ecto.Changeset{valid?: false}} = Users.reset_user_password(user, attrs)
      end

      assert Users.get_user_by_session_token(session).id == user.id
      assert Bcrypt.verify_pass("admin", Repo.get!(Brando.Users.User, user.id).password)
      assert_no_email_sent()
    end
  end

  describe "update_user_password/4" do
    test "needs the current password", %{user: user} do
      attrs = %{"password" => "a new password", "password_confirmation" => "a new password"}
      assert {:error, changeset} = Users.update_user_password(user, "wrong", attrs)
      assert {_, _} = changeset.errors[:current_password]
      assert {:error, _} = Users.update_user_password(user, nil, attrs)
    end

    test "keeps the current session and logs out the others", %{user: user} do
      current = Users.generate_user_session_token(user)
      other = Users.generate_user_session_token(user)
      @endpoint.subscribe(Users.live_socket_id(other))
      @endpoint.subscribe(Users.live_socket_id(current))
      :ok = Users.request_password_reset(user.email)
      reset = sent_token()

      attrs = %{"password" => "a new password", "password_confirmation" => "a new password"}
      assert {:ok, updated} = Users.update_user_password(user, "admin", attrs, current)

      assert Bcrypt.verify_pass("a new password", updated.password)
      refute updated.config.reset_password_on_first_login
      assert Users.get_user_by_session_token(current).id == user.id
      assert is_nil(Users.get_user_by_session_token(other))
      assert is_nil(Users.get_user_by_reset_password_token(reset))

      other_topic = Users.live_socket_id(other)
      current_topic = Users.live_socket_id(current)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^other_topic}
      refute_received %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^current_topic}
      assert_email_sent(subject: "Your password was changed")
    end

    test "changes the password without a mailer, with no email", %{user: user} do
      Application.delete_env(:brando, :mailer)
      attrs = %{"password" => "a new password", "password_confirmation" => "a new password"}
      assert {:ok, _} = Users.update_user_password(user, "admin", attrs)
      assert_no_email_sent()
    end
  end

  describe "send_password_reset/2" do
    test "a superuser sends another user a link", %{user: user} do
      admin = Factory.insert(:random_user, role: :superuser)

      assert {:ok, _} = Users.send_password_reset(user.id, admin)

      assert_email_sent(fn email ->
        assert email.subject == "Reset your password"
        assert email.text_body =~ "An administrator sent you this link"
        assert email.text_body =~ "/admin/reset-password/"
      end)
    end

    test "others may not, and nobody sends one to an inactive account", %{user: user} do
      editor = Factory.insert(:random_user, role: :editor)
      admin = Factory.insert(:random_user, role: :superuser)
      inactive = Factory.insert(:random_user, active: false)

      assert {:error, :forbidden} = Users.send_password_reset(user.id, editor)
      assert {:error, :inactive} = Users.send_password_reset(inactive.id, admin)
      assert_no_email_sent()
      assert {:ok, _} = Users.send_password_reset(editor.id, editor)
    end
  end

  describe "the emails" do
    test "are written in the user's language", %{user: user} do
      email = Users.UserNotifier.reset_password_instructions(%{user | language: "no"}, "https://example.com/r/abc")
      refute email.subject == "Reset your password"
      assert email.html_body =~ ~s(href="https://example.com/r/abc")
      assert email.text_body =~ "https://example.com/r/abc"
    end
  end
end
