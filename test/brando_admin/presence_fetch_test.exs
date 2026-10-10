defmodule BrandoAdmin.PresenceFetchTest do
  @moduledoc """
  `Phoenix.Presence` runs `fetch/2` for every diff in a task linked to the
  presence shard, and Brando's fetchers look the users up in the database.
  When that lookup failed, the task took the shard down with it, and with it
  every admin session tracked on it. In the suite this was the
  `presence-shard-owner-exited` flake: a leave looked up while the sandbox
  owner of the test that left was exiting, and the next test to mount an admin
  LiveView found the shard gone.

  No sandbox is checked out here, so every lookup fails, as one does when its
  owner has gone.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @shard :"Elixir.BrandoIntegration.Presence_shard0"

  for topic <- ["lobby", "url:/admin/pages"] do
    test "a users lookup that fails leaves the tracker running (#{topic})" do
      shard = Process.whereis(@shard)
      session = spawn(fn -> Process.sleep(:infinity) end)
      key = to_string(System.unique_integer([:positive]))

      log =
        capture_log(fn ->
          {:ok, _ref} = BrandoIntegration.Presence.track(session, unquote(topic), key, %{online_at: "1"})
          Brando.LiveCase.await_presence_idle()

          Process.exit(session, :kill)
          Brando.LiveCase.await_presence_idle()
        end)

      assert Process.whereis(@shard) == shard
      assert log =~ "could not look up"
    end
  end

  # Phoenix.Presence merges the fetched diff into the state it hands
  # handle_metas/4: a leave left out of it would keep the tab there for good,
  # and that user's last departure would never be recorded
  test "a lobby lookup that fails keeps every presence, by its key" do
    metas = [%{online_at: "1", url: "/admin"}]

    capture_log(fn ->
      assert %{42 => %{user: %{id: 42}, metas: ^metas}} =
               BrandoAdmin.Presence.LobbyFetcher.fetch(%{"42" => %{metas: metas}})
    end)
  end
end
