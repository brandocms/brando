defmodule BrandoAdmin.PresenceLastSeenTest do
  @moduledoc """
  The presence modal shows `last_active` for a user who is online and falls back
  to `users.last_login` for one who is not, so that column is what an editor
  reads as "last seen".

  Only two things write it: the login controller, and — for a departure —
  `LobbyFetcher.handle_metas/4`. It used to be `BrandoAdmin.Chrome`, which is
  the only subscriber to the "presence" topic and is a sticky LiveView, one per
  open admin browser. The write was therefore performed by *other people's*
  browsers: when the last admin left, the broadcast went out and the only
  process that would have persisted it was the one dying.

  On a site whose two editors rarely overlap that means the timestamp only ever
  moves when someone happens to be watching. Reported from production as a
  user's last-seen frozen twelve days back while they had been using the site
  daily — and it had last moved on an evening the other editor was demonstrably
  online.

  These cover the departure itself. A user who is merely closing one of several
  tabs has not left, and must not have a departure recorded.
  """

  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias BrandoAdmin.Presence.LobbyFetcher

  @pubsub Brando.pubsub()

  setup do
    user = Brando.Factory.insert(:random_user, last_login: ~N[2020-01-01 00:00:00])
    Phoenix.PubSub.subscribe(@pubsub, "presence")
    {:ok, user: user}
  end

  defp leave(user, remaining_metas) do
    key = to_string(user.id)

    leaves = %{
      key => %{
        user: %{id: user.id, name: user.name, avatar: nil, last_login: user.last_login},
        metas: []
      }
    }

    presences = if remaining_metas == [], do: %{}, else: %{key => remaining_metas}

    LobbyFetcher.handle_metas(%{}, leaves, presences, @pubsub)
  end

  defp reload(user), do: Brando.Repo.get!(Brando.Users.User, user.id)

  test "a user leaving with no sessions left has the departure recorded", %{user: user} do
    leave(user, [])

    assert_receive {BrandoAdmin.Presence, {:presence, %{user_left: _}}}

    refreshed = reload(user)

    assert NaiveDateTime.compare(refreshed.last_login, user.last_login) == :gt,
           "the departure was not recorded — last seen only moves when another admin is watching"
  end

  test "closing one of several tabs is not a departure", %{user: user} do
    leave(user, [%{online_at: "1", url: "/admin", active: true}])

    assert_receive {BrandoAdmin.Presence, {:presence, %{user_left: _}}}

    assert reload(user).last_login == user.last_login,
           "a still-connected user was recorded as having left"
  end

  test "a database failure does not take the tracker down", %{user: user} do
    # The presence process handles every diff for every connected admin, so a
    # raise here is not a missed timestamp, it is presence going dark. Deleting
    # the row makes `set_last_login/1` fail against a primary key that is gone.
    Brando.Repo.delete!(user)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        leave(user, [])
      end)

    assert log =~ "could not record last seen"
    assert_receive {BrandoAdmin.Presence, {:presence, %{user_left: _}}}
  end
end
