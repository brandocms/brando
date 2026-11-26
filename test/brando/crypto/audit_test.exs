defmodule Brando.Crypto.AuditTest do
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Crypto.Audit
  alias Brando.Crypto.Marker
  alias Brando.Factory
  alias Brando.MCP.Setting
  alias Brando.Notifications.Route
  alias Brando.Notifications.Routing
  alias Brando.Test.ForeignSecret
  alias Brando.Users
  alias Brando.Users.Passkey
  alias Brando.Users.RecoveryCode
  alias Brando.Users.Security
  alias Brando.Users.SecurityEvent
  alias Brando.Users.UserConfig
  alias Brando.Webhooks
  alias Brando.Webhooks.Webhook

  @none %{
    users: 0,
    webhooks: 0,
    notification_routes: 0,
    figma_token: 0,
    figma_app: 0,
    figma_connection: 0,
    figma_pending: 0
  }

  defp user(attrs \\ []), do: Factory.insert(:random_user, Keyword.merge([config: %UserConfig{}], attrs))

  defp security(user), do: Repo.get_by(Security, user_id: user.id)
  defp recovery_codes(user), do: Repo.aggregate(from(c in RecoveryCode, where: c.user_id == ^user.id), :count)

  defp webhook(prefix, id), do: Repo.get!(Webhook, id, prefix: prefix || "public")
  defp route(prefix, id), do: Repo.get!(Route, id, prefix: prefix || "public")

  defp create_tables(prefix) do
    Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

    for table <- ~w(webhooks webhook_deliveries notification_routes notification_deliveries activity_events),
        do: Repo.query!(~s|CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
  end

  # A site with an environment of each status: active, suspended, archived
  defp sites! do
    Brando.Tenant.Cache.clear()
    on_exit(fn -> Brando.Tenant.Cache.clear() end)

    for {key, status} <- [{"crypto-a", :active}, {"crypto-b", :suspended}, {"crypto-c", :archived}] do
      {:ok, site} =
        Brando.Tenant.Registry.create_site(%{
          name: key,
          key: key,
          languages: ["en"],
          default_language: "en",
          status: status,
          delivery_mode: :dynamic
        })

      {:ok, _} = Brando.Tenant.Registry.create_environment(site, %{name: "Production", key: "production", live: true})
      prefix = Brando.Tenant.prefix(key, "production")
      create_tables(prefix)
      prefix
    end
  end

  describe "run/0" do
    test "counts nothing in a database this secret wrote" do
      ForeignSecret.two_factor!(user(), true)
      ForeignSecret.webhook!(nil, true)
      ForeignSecret.route!(nil, :slack, true)
      ForeignSecret.figma_setting!(%{token: true, app: true, connection: true, pending: true})

      assert Audit.run() == @none
      refute Audit.unreadable?(Audit.run())
    end

    test "counts each kind another secret wrote" do
      ForeignSecret.two_factor!(user(), false)
      ForeignSecret.two_factor!(user(), false)
      ForeignSecret.two_factor!(user(), true)
      ForeignSecret.webhook!(nil, false)
      ForeignSecret.webhook!(nil, true)
      ForeignSecret.route!(nil, :teams, false)
      ForeignSecret.figma_setting!(%{token: false, app: false, connection: true, pending: false})

      assert Audit.run() == %{
               @none
               | users: 2,
                 webhooks: 1,
                 notification_routes: 1,
                 figma_token: 1,
                 figma_app: 1,
                 figma_pending: 1
             }
    end

    test "counts webhooks and routes that send or resume by themselves, not those paused by hand" do
      ForeignSecret.webhook!(nil, false)
      ForeignSecret.webhook!(nil, false, active: false, paused_reason: :environment_copy)
      ForeignSecret.webhook!(nil, false, active: false, paused_reason: :manual)
      ForeignSecret.webhook!(nil, false, active: false, paused_reason: :failures)
      ForeignSecret.route!(nil, :slack, false, active: false, paused_reason: :environment_copy)
      ForeignSecret.route!(nil, :slack, false, active: false, paused_reason: :manual)

      assert %{webhooks: 2, notification_routes: 1} = Audit.run()
    end

    test "an email route has no URL and is never unreadable, beside Slack and Teams routes" do
      ForeignSecret.route!(nil, :email, false)
      ForeignSecret.route!(nil, :slack, false)
      ForeignSecret.route!(nil, :teams, false)

      assert %{notification_routes: 2} = Audit.run()
    end

    test "reads in batches past the first" do
      for _ <- 1..501, do: ForeignSecret.webhook!(nil, false)

      assert %{webhooks: 501} = Audit.run()
    end

    test "with tenancy, counts in public and every site environment, archived and suspended sites' too" do
      put_test_env(:tenancy_mode, :multi)
      prefixes = sites!()

      ForeignSecret.webhook!(nil, false)
      for prefix <- prefixes, do: ForeignSecret.webhook!(prefix, false)
      for prefix <- prefixes, do: ForeignSecret.route!(prefix, :slack, false)

      assert Audit.prefixes() == [nil | prefixes]
      assert %{webhooks: 4, notification_routes: 3} = Audit.run()
    end
  end

  describe "forget/2" do
    test "is for the system and superusers" do
      assert {:error, :forbidden} = Audit.forget(user(role: :admin))
      assert {:ok, %{failed: []}} = Audit.forget(user(role: :superuser))
      assert {:ok, %{failed: []}} = Audit.forget(:system)
    end

    test "with group authorization, too" do
      put_test_env(Brando.Authorization, enabled: true)

      assert {:error, :forbidden} = Audit.forget(user(role: :admin))
    end

    test "resets an unreadable two-factor secret as a reset does, but keeps passkeys" do
      admin = user(role: :superuser)
      other = user(role: :editor)
      ForeignSecret.two_factor!(other, false)
      Repo.insert!(%Passkey{user_id: other.id, credential_id: "cred", cose_key: "key", sign_count: 0, name: "Key"})
      session = Users.generate_user_session_token(other)
      Repo.update_all(from(s in Security, where: s.user_id == ^other.id), set: [failed_attempts: 4])

      assert {:ok, %{users: 1, marker: :written, failed: []}} = Audit.forget(admin)

      assert %Security{totp_secret: nil, totp_enabled_at: nil, failed_attempts: 0} = security(other)
      assert recovery_codes(other) == 0
      assert Repo.aggregate(from(p in Passkey, where: p.user_id == ^other.id), :count) == 1
      assert is_nil(Users.get_user_by_session_token(session))

      assert [%SecurityEvent{actor_id: actor_id, details: %{"reason" => "unreadable"}}] =
               Repo.all(from(e in SecurityEvent, where: e.user_id == ^other.id and e.action == :two_factor_reset))

      assert actor_id == admin.id
    end

    test "the admin who runs it keeps the session they run it from" do
      admin = user(role: :superuser)
      ForeignSecret.two_factor!(admin, false)
      kept = Users.generate_user_session_token(admin)
      other = Users.generate_user_session_token(admin)

      assert {:ok, %{users: 1}} = Audit.forget(admin, keep_id: Users.token_id(kept))

      assert Users.get_user_by_session_token(kept)
      refute Users.get_user_by_session_token(other)
    end

    test "leaves readable values alone, also with a foreign marker" do
      readable_user = user()
      readable = ForeignSecret.two_factor!(readable_user, true)
      hook = ForeignSecret.webhook!(nil, true)
      route = ForeignSecret.route!(nil, :slack, true)
      setting = ForeignSecret.figma_setting!(%{token: true, app: true, connection: true, pending: true})
      Repo.insert!(%Marker{id: 1, value: ForeignSecret.encrypt("brando", "brando.crypto_marker"), host: "localhost"})

      assert {:ok, result} = Audit.forget(:system)
      assert Map.take(result, Audit.kinds()) == @none

      assert security(readable_user).totp_secret == readable
      assert recovery_codes(readable_user) == 2
      assert webhook(nil, hook.id).active
      assert route(nil, route.id).active

      assert Repo.reload(setting) |> Map.take([:figma_token, :figma_client_id, :figma_oauth_pending]) ==
               Map.take(setting, [:figma_token, :figma_client_id, :figma_oauth_pending])

      assert Marker.state().key == :ours
    end

    test "pauses unreadable webhooks and routes by hand, secrets kept, so going live does not resume them" do
      prefix = "tenant_crypto-copy_production"
      put_test_env(:tenancy_mode, :multi)
      create_tables(prefix)
      Brando.Tenant.Cache.clear()
      on_exit(fn -> Brando.Tenant.Cache.clear() end)

      {:ok, site} =
        Brando.Tenant.Registry.create_site(%{
          name: "Copy",
          key: "crypto-copy",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, _} = Brando.Tenant.Registry.create_environment(site, %{name: "Production", key: "production", live: true})

      copied = ForeignSecret.webhook!(prefix, false, active: false, paused_reason: :environment_copy)
      active = ForeignSecret.route!(prefix, :slack, false)
      email = ForeignSecret.route!(prefix, :email, false)

      assert {:ok, %{webhooks: 1, notification_routes: 1, failed: []}} = Audit.forget(:system)

      assert %Webhook{active: false, paused_reason: :manual, secret_ciphertext: ciphertext} = webhook(prefix, copied.id)
      assert ciphertext == copied.secret_ciphertext
      assert %Route{active: false, paused_reason: :manual} = route(prefix, active.id)
      assert %Route{active: true} = route(prefix, email.id)

      assert Webhooks.after_going_live(prefix) == 0
      assert %Webhook{active: false} = webhook(prefix, copied.id)
    end

    test "clears each Figma group that does not decrypt, through the path that removes it, and keeps the others" do
      setting = ForeignSecret.figma_setting!(%{token: true, app: false, connection: false, pending: false})

      assert {:ok, %{figma_token: 0, figma_app: 1, figma_connection: 1, figma_pending: 1}} = Audit.forget(:system)

      assert %Setting{
               figma_token: token,
               figma_client_id: nil,
               figma_client_secret: nil,
               figma_oauth_access_token: nil,
               figma_oauth_connected_at: nil,
               figma_oauth_pending: nil
             } = Repo.reload(setting)

      assert token == setting.figma_token
      assert {:ok, "value"} = Brando.MCP.figma_token(Brando.MCP.tenant(nil, nil))
    end

    test "an unreadable pasted token goes; a readable app and connection stay" do
      setting = ForeignSecret.figma_setting!(%{token: false, app: true, connection: true})

      assert {:ok, %{figma_token: 1, figma_app: 0, figma_connection: 0}} = Audit.forget(:system)

      assert %Setting{figma_token: nil, figma_client_id: client_id, figma_oauth_access_token: access} =
               Repo.reload(setting)

      assert client_id == setting.figma_client_id and access == setting.figma_oauth_access_token
    end

    test "does not undo what was written meanwhile" do
      user = user()
      stale = ForeignSecret.two_factor!(user, false)
      enrolled = ForeignSecret.two_factor!(user, true)
      refute Brando.Users.TwoFactor.forget_unreadable(user.id, stale, :system)
      assert security(user).totp_secret == enrolled

      hook = ForeignSecret.webhook!(nil, false)
      Repo.update_all(from(w in Webhook, where: w.id == ^hook.id), set: [secret_ciphertext: "rotated"])
      refute Webhooks.pause_unreadable_one(nil, hook, :system)
      assert webhook(nil, hook.id).active

      route = ForeignSecret.route!(nil, :slack, false)
      Repo.update_all(from(r in Route, where: r.id == ^route.id), set: [url_ciphertext: "replaced"])
      refute Routing.pause_unreadable_one(nil, route, :system)
      assert route(nil, route.id).active

      setting =
        %{token: false}
        |> ForeignSecret.figma_setting!()
        |> Repo.preload([:site, :environment])

      saved = Brando.Crypto.encrypt("new-token", "mcp.figma_token:0:0")
      Repo.update_all(from(s in Setting, where: s.id == ^setting.id), set: [figma_token: saved])
      refute Brando.MCP.forget_unreadable_figma_token(setting, :system)
      assert Repo.reload(setting).figma_token == saved

      # The OAuth groups are read again under the row's lock
      Repo.delete!(setting)
      landed = ForeignSecret.figma_setting!(%{}) |> Repo.preload([:site, :environment])
      stale_view = %{landed | figma_oauth_pending: ForeignSecret.encrypt("pending", "mcp.figma_pending:0:0")}
      pending = Brando.Crypto.encrypt("pending", "mcp.figma_pending:0:0")
      Repo.update_all(from(s in Setting, where: s.id == ^landed.id), set: [figma_oauth_pending: pending])
      assert Brando.Figma.OAuth.forget_unreadable(stale_view, :system) == []
      assert Repo.reload(landed).figma_oauth_pending == pending
    end

    test "run twice, the second run finds nothing" do
      ForeignSecret.two_factor!(user(), false)
      ForeignSecret.webhook!(nil, false)

      assert {:ok, %{users: 1, webhooks: 1}} = Audit.forget(:system)
      assert {:ok, second} = Audit.forget(:system)
      assert Map.take(second, Audit.kinds()) == @none
      assert Audit.run() == @none
    end

    test "before a serving start, keeps the other host, so that start still pauses and records the move" do
      Repo.insert!(%Marker{
        id: 1,
        value: ForeignSecret.encrypt("brando", "brando.crypto_marker"),
        host: "prod.example.com"
      })

      unreadable = ForeignSecret.webhook!(nil, false)
      active = ForeignSecret.webhook!(nil, true)
      email = ForeignSecret.route!(nil, :email, true)

      assert {:ok, %{webhooks: 1, marker: :written}} = Audit.forget(:system)
      assert %{key: :ours, host: :other} = Marker.state()
      refute webhook(nil, unreadable.id).active

      ExUnit.CaptureLog.capture_log(fn -> :ok = Marker.check_at_start() end)

      refute webhook(nil, active.id).active
      refute route(nil, email.id).active
      assert %Marker{moved_from: "prod.example.com", moved_key: "ours"} = Repo.get!(Marker, 1)
      assert %{key: :ours, host: :same} = Marker.state()
    end

    test "a marker written where there was none takes this host" do
      assert {:ok, %{marker: :written}} = Audit.forget(:system)
      assert %{key: :ours, host: :same} = Marker.state()
    end

    test "after it, another secret here reads as this installation's secret changing, not as the move" do
      Repo.insert!(%Marker{
        id: 1,
        value: ForeignSecret.encrypt("brando", "brando.crypto_marker"),
        host: Marker.host(),
        moved_from: "prod.example.com",
        moved_at: DateTime.utc_now(),
        moved_key: "foreign",
        paused: []
      })

      assert Brando.Doctor.Checks.EncryptedData.cause(Marker.state()) == {:moved, "prod.example.com"}
      assert {:ok, %{marker: :written}} = Audit.forget(:system)

      # The secret is mistyped later
      put_test_env(Brando.Crypto, secret: String.duplicate("a mistyped secret ", 3))
      assert %{key: :foreign} = Marker.state()
      assert Brando.Doctor.Checks.EncryptedData.cause(Marker.state()) == :changed_here
      # The notice of the move stays until it is dismissed
      assert %{from: "prod.example.com"} = Marker.move_notice()
    end

    test "a schema that fails leaves the marker as it was, and a second run finishes it" do
      prefix = "tenant_crypto-a_production"
      put_test_env(:tenancy_mode, :multi)
      [^prefix | _] = sites!()
      Repo.insert!(%Marker{id: 1, value: ForeignSecret.encrypt("brando", "brando.crypto_marker"), host: "localhost"})

      broken = ForeignSecret.webhook!(prefix, false)
      public = ForeignSecret.webhook!(nil, false)

      Repo.query!(
        ~s|CREATE FUNCTION "#{prefix}".refuse() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'refused'; END $$|
      )

      Repo.query!(
        ~s|CREATE TRIGGER refuse BEFORE UPDATE ON "#{prefix}".webhooks FOR EACH ROW EXECUTE FUNCTION "#{prefix}".refuse()|
      )

      {result, log} = ExUnit.CaptureLog.with_log(fn -> Audit.forget(:system) end)

      assert {:ok, %{failed: [^prefix], marker: :kept, webhooks: 1}} = result
      assert log =~ "Could not clean up #{prefix}"
      assert Marker.state().key == :foreign
      refute webhook(nil, public.id).active

      Repo.query!(~s|DROP TRIGGER refuse ON "#{prefix}".webhooks|)

      assert {:ok, %{failed: [], marker: :written, webhooks: 1}} = Audit.forget(:system)
      refute webhook(prefix, broken.id).active
      assert Marker.state().key == :ours
    end
  end
end
