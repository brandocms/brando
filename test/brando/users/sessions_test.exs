defmodule Brando.Users.SessionsTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.SecurityEvent
  alias Brando.Users.UserConfig
  alias Brando.Users.UserToken

  defp user(attrs \\ []),
    do: Factory.insert(:random_user, Keyword.merge([role: :editor, config: %UserConfig{}], attrs))

  defp chrome, do: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 Chrome/130.0 Safari/537.36"

  test "a session notes its browser and address, and lists newest use first" do
    user = user()
    first = Users.generate_user_session_token(user, %{ip: "10.0.0.1", user_agent: chrome()})
    second = Users.generate_user_session_token(user, %{ip: "10.0.0.2", user_agent: "curl/8"})

    Repo.update_all(from(t in UserToken, where: t.token == ^first),
      set: [last_used_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)]
    )

    assert [%{id: second_id, ip: "10.0.0.2", token: nil}, %{id: first_id, user_agent: "Mozilla" <> _}] =
             Users.list_sessions(user)

    assert second_id == Users.token_id(second)
    assert first_id == Users.token_id(first)
    assert BrandoAdmin.Components.TwoFactor.browser(chrome()) == "Chrome on macOS"
  end

  test "a session in use is noted at most every five minutes" do
    user = user()
    token = Users.generate_user_session_token(user)
    hour_ago = NaiveDateTime.add(NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second), -3600)
    Repo.update_all(from(t in UserToken, where: t.token == ^token), set: [last_used_at: hour_ago])

    Users.touch_session(token)
    [%{last_used_at: touched}] = Users.list_sessions(user)
    assert NaiveDateTime.diff(NaiveDateTime.utc_now(), touched) < 5

    minute_ago = NaiveDateTime.add(NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second), -60)
    Repo.update_all(from(t in UserToken, where: t.token == ^token), set: [last_used_at: minute_ago])
    Users.touch_session(token)
    assert [%{last_used_at: ^minute_ago}] = Users.list_sessions(user)
  end

  test "a user logs out one of their sessions, but not someone else's" do
    user = user()
    other = user()
    token = Users.generate_user_session_token(user)
    others = Users.generate_user_session_token(other)
    [%{id: id}] = Users.list_sessions(user)
    [%{id: others_id}] = Users.list_sessions(other)

    assert {:error, :not_found} = Users.revoke_session(user, others_id)
    assert Users.get_user_by_session_token(others)

    assert :ok = Users.revoke_session(user, id)
    refute Users.get_user_by_session_token(token)
    assert [:session_revoked] = Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id, select: e.action)
  end

  test "logging out the other sessions keeps this one" do
    user = user()
    current = Users.generate_user_session_token(user)
    other = Users.generate_user_session_token(user)

    assert :ok = Users.log_out_everywhere(user, user, except_id: Users.token_id(current))
    assert Users.get_user_by_session_token(current)
    refute Users.get_user_by_session_token(other)
  end

  test "an administrator logs a user out everywhere, which is logged with who did it" do
    admin = user(role: :superuser)
    editor = user()
    user = user()
    token = Users.generate_user_session_token(user)

    assert {:error, :forbidden} = Users.log_out_everywhere(user, editor)
    assert Users.get_user_by_session_token(token)

    assert :ok = Users.log_out_everywhere(user, admin)
    refute Users.get_user_by_session_token(token)

    assert [%{action: :sessions_revoked, actor_id: actor_id}] =
             Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id)

    assert actor_id == admin.id
  end
end
