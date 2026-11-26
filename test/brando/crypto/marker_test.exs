defmodule Brando.Crypto.MarkerTest do
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Crypto.Marker
  alias Brando.Factory
  alias Brando.Notifications.Route
  alias Brando.Test.ForeignSecret
  alias Brando.Webhooks.Webhook

  @context "brando.crypto_marker"

  defp marker!(value, host),
    do: Repo.insert!(%Marker{id: 1, value: value, host: host, paused: []})

  defp ours, do: Brando.Crypto.encrypt("brando", @context)
  defp foreign, do: ForeignSecret.encrypt("brando", @context)

  defp row, do: Repo.one(from(m in Marker, where: m.id == 1))
  defp webhook(prefix, id), do: Repo.get!(Webhook, id, prefix: prefix || "public")
  defp route(prefix, id), do: Repo.get!(Route, id, prefix: prefix || "public")

  # What it logs: the warnings too, which the test configuration drops
  defp check do
    previous = Logger.level()
    Logger.configure(level: :warning)

    try do
      {:ok, ExUnit.CaptureLog.capture_log([level: :warning], fn -> :ok = Marker.check_at_start() end)}
    after
      Logger.configure(level: previous)
    end
  end

  describe "state/0" do
    test "tells the key and the host apart" do
      assert %{key: :none, host: nil} = Marker.state()

      marker!(ours(), Marker.host())
      assert %{key: :ours, host: :same} = Marker.state()

      Repo.update_all(Marker, set: [value: foreign(), host: "prod.example.com"])
      assert %{key: :foreign, host: :other} = Marker.state()
    end

    test "is unknown before the migration" do
      Repo.query!("DROP TABLE public.crypto_marker")
      assert %{key: :unknown} = Marker.state()

      {:ok, log} = check()
      assert log =~ "run the migrations"
    end
  end

  describe "at start" do
    test "runs only where the endpoint serves, outside the SQL sandbox" do
      assert Marker.children() == []
    end

    test "writes the marker when there is none and everything is readable" do
      ForeignSecret.two_factor!(Factory.insert(:random_user), true)

      {:ok, _log} = check()

      assert %{key: :ours, host: :same, marker: %Marker{moved_at: nil}} = Marker.state()
    end

    test "writes nothing when there is none and something is unreadable, and warns" do
      ForeignSecret.two_factor!(Factory.insert(:random_user), false)
      hook = ForeignSecret.webhook!(nil, true)

      {:ok, log} = check()

      assert log =~ "encrypted with another secret"
      assert log =~ "mix brando.doctor"
      assert is_nil(row())
      # Nothing is known about where it came from: nothing is paused
      assert webhook(nil, hook.id).active
    end

    test "a foreign marker on this host is only warned about" do
      marker!(foreign(), Marker.host())
      hook = ForeignSecret.webhook!(nil, true)
      before = row()

      {:ok, log} = check()

      assert log =~ "encrypted with another secret"
      assert row() == before
      assert webhook(nil, hook.id).active
    end

    test "another host's database: every active webhook and route is paused by hand, once" do
      marker!(ours(), "prod.example.com")
      hook = ForeignSecret.webhook!(nil, true, name: "Deploy")
      failing = ForeignSecret.webhook!(nil, true, active: false, paused_reason: :failures)
      email = ForeignSecret.route!(nil, :email, true)
      slack = ForeignSecret.route!(nil, :slack, true)

      {:ok, log} = check()

      assert log =~ "written by prod.example.com"
      assert %Webhook{active: false, paused_reason: :manual, secret_ciphertext: kept} = webhook(nil, hook.id)
      assert kept == hook.secret_ciphertext
      assert %Webhook{paused_reason: :failures} = webhook(nil, failing.id)
      assert %Route{active: false, paused_reason: :manual} = route(nil, email.id)
      assert %Route{active: false, paused_reason: :manual} = route(nil, slack.id)

      assert %Marker{host: host, moved_from: "prod.example.com", moved_key: "ours", moved_at: %DateTime{}, paused: paused} =
               row()

      assert host == Marker.host()

      assert [
               %{"prefix" => nil, "kind" => "webhook", "count" => 1, "named" => [%{"id" => id, "name" => "Deploy"}]},
               %{"prefix" => nil, "kind" => "notification_route", "count" => 2}
             ] = paused

      assert id == hook.id
      assert %{from: "prod.example.com", paused: ^paused} = Marker.move_notice()

      # The next start, or a second node, finds this host
      Repo.update_all(Webhook, set: [active: true, paused_reason: nil])
      {:ok, _log} = check()
      assert webhook(nil, hook.id).active
      assert row().moved_at
    end

    test "another host's database: those paused for an environment copy are paused by hand, so going live resumes none" do
      marker!(ours(), "prod.example.com")
      hook = ForeignSecret.webhook!(nil, true, active: false, paused_reason: :environment_copy)
      teams = ForeignSecret.route!(nil, :teams, true, active: false, paused_reason: :environment_copy)
      by_hand = ForeignSecret.webhook!(nil, true, active: false, paused_reason: :manual)

      {:ok, _log} = check()

      assert %Webhook{active: false, paused_reason: :manual} = webhook(nil, hook.id)
      assert %Route{active: false, paused_reason: :manual} = route(nil, teams.id)

      assert [
               %{"kind" => "webhook", "count" => 1, "named" => [%{"id" => hook_id}]},
               %{"kind" => "notification_route", "count" => 1}
             ] = row().paused

      assert hook_id == hook.id
      # Paused by hand before: not counted again
      refute hook_id == by_hand.id

      assert Brando.Webhooks.after_going_live("public") == 0
      assert Brando.Notifications.Routing.after_going_live("public") == 0
      refute webhook(nil, hook.id).active
      refute route(nil, teams.id).active
    end

    test "another host's database with a foreign secret: paused, recorded, and the marker kept as it was" do
      marker!(foreign(), "prod.example.com")
      hook = ForeignSecret.webhook!(nil, false)

      {:ok, log} = check()

      assert log =~ "encrypted with another secret"
      refute webhook(nil, hook.id).active
      assert %Marker{moved_key: "foreign", moved_from: "prod.example.com", value: value} = row()
      assert Brando.Crypto.decrypt(value, @context) == :error
      assert %{key: :foreign, host: :same} = Marker.state()
    end

    test "two nodes starting at once pause once" do
      marker!(ours(), "prod.example.com")
      ForeignSecret.webhook!(nil, true)
      parent = self()

      [:ok, :ok] =
        for _ <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Brando.Repo.repo(), parent, self())
            Marker.check_at_start()
          end)
        end
        |> Task.await_many()

      assert [%{"count" => 1}] = row().paused
      assert Repo.aggregate(from(e in Brando.Activity.Event, where: e.schema == ^to_string(Webhook)), :count) == 1
    end

    test "a node with the wrong secret beside one with the right one rewrites nothing" do
      marker!(ours(), Marker.host())
      before = row()

      # Another secret than the one the marker was written with
      put_test_env(Brando.Crypto, secret: String.duplicate("the-wrong-secret", 3))
      {:ok, log} = check()
      assert log =~ "encrypted with another secret"
      assert row() == before
    end

    for mode <- [:none, :single, :multi] do
      @tag tenancy: mode
      test "pauses in public and every site environment, tenancy #{mode}", %{tenancy: mode} do
        put_test_env(:tenancy_mode, mode)
        marker!(ours(), "prod.example.com")
        public = ForeignSecret.webhook!(nil, true)

        prefixes =
          if mode == :none do
            []
          else
            Brando.Tenant.Cache.clear()
            on_exit(fn -> Brando.Tenant.Cache.clear() end)

            for {key, status} <- [{"moved-a", :active}, {"moved-b", :archived}] do
              {:ok, site} =
                Brando.Tenant.Registry.create_site(%{
                  name: key,
                  key: key,
                  languages: ["en"],
                  default_language: "en",
                  status: status,
                  delivery_mode: :dynamic
                })

              {:ok, _} = Brando.Tenant.Registry.create_environment(site, %{name: "P", key: "production", live: true})
              prefix = Brando.Tenant.prefix(key, "production")
              Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

              for table <- ~w(webhooks notification_routes activity_events),
                  do: Repo.query!(~s|CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)

              prefix
            end
          end

        hooks = for prefix <- prefixes, do: {prefix, ForeignSecret.webhook!(prefix, true)}
        routes = for prefix <- prefixes, do: {prefix, ForeignSecret.route!(prefix, :teams, true)}

        {:ok, _log} = check()

        refute webhook(nil, public.id).active
        for {prefix, hook} <- hooks, do: refute(webhook(prefix, hook.id).active)
        for {prefix, route} <- routes, do: refute(route(prefix, route.id).active)
        assert length(row().paused) == 1 + 2 * length(prefixes)
      end
    end
  end

  describe "the notice of a move" do
    test "stays until it is dismissed" do
      marker!(ours(), "prod.example.com")
      {:ok, _log} = check()
      assert Marker.move_notice()

      assert :ok = Marker.dismiss_paused()
      assert is_nil(Marker.move_notice())
    end

    test "is not there without a move" do
      marker!(ours(), Marker.host())
      assert is_nil(Marker.move_notice())
    end
  end
end
