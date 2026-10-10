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
