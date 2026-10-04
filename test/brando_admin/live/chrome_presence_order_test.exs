defmodule BrandoAdmin.ChromePresenceOrderTest do
  @moduledoc """
  The avatar strip shows who is online. Your own avatar leads it, whatever
  order the users come back from the database in.
  """

  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest

  alias Brando.Authorization.Scope

  defp go_online(user, scope) do
    test_pid = self()

    pid =
      spawn_link(fn ->
        {:ok, _} =
          Brando.presence().track(self(), "lobby", user.id, %{
            online_at: to_string(System.system_time(:second)),
            active: true,
            url: "/admin",
            scope: scope
          })

        send(test_pid, {:tracked, user.id})
        Process.sleep(:infinity)
      end)

    assert_receive {:tracked, _}
    pid
  end

  test "the signed-in user is the first online avatar" do
    other = Brando.Factory.insert(:random_user)
    me = Brando.Factory.insert(:random_user)
    scope = Scope.current(me)

    go_online(other, scope)
    go_online(me, scope)

    token = Brando.Users.generate_user_session_token(me)
    {:ok, view, _} = live_isolated(build_conn(), BrandoAdmin.Chrome, session: %{"user_token" => token})

    online_ids =
      view
      |> element("#presences-active")
      |> render()
      |> then(&Regex.scan(~r/data-user-id="(\d+)"/, &1, capture: :all_but_first))
      |> List.flatten()

    assert online_ids == [to_string(me.id), to_string(other.id)]
  end
end
