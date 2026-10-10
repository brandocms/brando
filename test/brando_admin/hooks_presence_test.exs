defmodule BrandoAdmin.HooksPresenceTest do
  # URL presence departures reaching an admin LiveView. The URL presence
  # fetcher gives `user: nil` for an account it cannot load (deleted, or in
  # tests created in a sandbox the presence process cannot see).
  use ExUnit.Case, async: true

  alias BrandoAdmin.Hooks

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, presences: %{}, presence_ids: %{}}, assigns)
    }
  end

  defp leave(presence), do: {BrandoAdmin.Presence, {:uri_presence, %{user_left: presence}}}

  defp push_events(socket), do: socket.private.live_temp |> Map.get(:push_events, []) |> Enum.reverse()

  describe "a tab of a user who no longer loads leaving" do
    test "while another of their tabs stays leaves the socket as it was" do
      presence = %{user: nil, left: [%{tab: "closed"}], metas: [%{tab: "open"}]}

      assert {:halt, socket} = Hooks.handle_info(leave(presence), socket())
      assert socket.assigns.presences == %{}
      assert socket.assigns.presence_ids == %{}
      assert push_events(socket) == []
    end

    test "as their last leaves the socket as it was" do
      presence = %{user: nil, left: [%{tab: "closed"}], metas: []}

      assert {:halt, socket} = Hooks.handle_info(leave(presence), socket())
      assert socket.assigns.presences == %{}
      assert push_events(socket) == []
    end
  end

  describe "a tab of a deleted user leaving, with the presence key as `user_id`" do
    # Another editor still sees the field locks the user's tabs held, sent
    # with their real id, until the departures release them by that id.
    test "while another of their tabs stays releases the closed tab's field" do
      presence = %{user: nil, user_id: 7, left: [%{tab: "closed"}], metas: [%{tab: "open"}]}

      assert {:halt, socket} = Hooks.handle_info(leave(presence), socket())
      assert socket.assigns.presences == %{}
      assert push_events(socket) == [["b:set_active_field", %{user_id: 7, field: nil, tab: "closed"}]]
    end

    test "as their last clears them" do
      presence = %{user: nil, user_id: 7, left: [%{tab: "closed"}], metas: []}
      shown = socket(%{presences: %{7 => %{id: 7}}, presence_ids: %{7 => 1}})

      assert {:halt, socket} = Hooks.handle_info(leave(presence), shown)
      assert socket.assigns.presences == %{}
      assert socket.assigns.presence_ids == %{}
      assert push_events(socket) == [["b:clear_user_presence", %{user_id: 7}]]
    end
  end

  test "a URL presence departure carries the presence key as `user_id`" do
    topic = "url:/admin/hooks-presence-test/#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Brando.pubsub(), topic)
    leaves = %{"7" => %{user: nil, metas: [%{tab: "closed"}]}}

    BrandoAdmin.Presence.UrlFetcher.handle_metas(topic, %{}, leaves, %{}, Brando.pubsub())

    assert_receive {BrandoAdmin.Presence, {:uri_presence, %{user_left: %{user: nil, user_id: 7, metas: []}}}}
  end

  test "a closed tab of a user with another tab open releases only that tab's field" do
    user = %{id: 7, name: "Editor"}
    presence = %{user: user, left: [%{tab: "closed"}, %{tab: "open"}], metas: [%{tab: "open"}]}

    assert {:halt, socket} = Hooks.handle_info(leave(presence), socket())
    assert %{7 => %{id: 7, frontend?: false}} = socket.assigns.presences

    assert push_events(socket) == [
             ["b:set_active_field", %{user_id: 7, field: nil, tab: "closed"}]
           ]
  end
end
