defmodule Brando.ReleaseColdTest do
  # Brando.Release as `bin/my_app eval` runs it: a new VM, `mix run
  # --no-start` with the test build and configuration, where nothing is
  # started, the repo included, and the function starts what it needs. Its
  # writes commit, so the data is committed here first, outside the sandbox,
  # and removed after each test; synchronous, so no other test sees it.
  use ExUnit.Case, async: false

  import Brando.Test.Support
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Crypto.Marker
  alias Brando.Test.ForeignSecret
  alias Brando.Users.Passkey
  alias Brando.Users.RecoveryCode
  alias Brando.Users.Security
  alias Brando.Users.SecurityEvent
  alias Brando.Users.User
  alias Brando.Users.UserToken
  alias Brando.Webhooks.Webhook
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag timeout: 180_000

  @prefix "tenant_cold-release_production"

  @script ~S"""
  defmodule BrandoIntegrationWeb.Endpoint do
    use Phoenix.Endpoint, otp_app: :brando
  end

  # Nothing is started: not the repo, Brando's processes, PubSub, the
  # endpoint, or plug_crypto's key cache
  nil = Process.whereis(BrandoIntegration.Repo)
  nil = Process.whereis(Brando.Supervisor)
  nil = Process.whereis(BrandoIntegration.PubSub)
  nil = Process.whereis(BrandoIntegrationWeb.Endpoint)
  :undefined = :ets.whereis(Plug.Crypto.Keys)

  if System.get_env("SECRET_SOURCE") == "secret_key_base", do: Application.delete_env(:brando, Brando.Crypto)
  if System.get_env("TENANCY") == "multi", do: Application.put_env(:brando, :tenancy_mode, :multi)
  Logger.configure(level: :warning)

  {call, _binding} = Code.eval_string(System.fetch_env!("CALL"))
  IO.puts("returned " <> inspect(call))
  """

  setup do
    on_exit(fn ->
      unboxed(fn ->
        Repo.query!(~s|DROP SCHEMA IF EXISTS "#{@prefix}" CASCADE|)
        Repo.delete_all(from(s in Brando.Sites.Site, where: s.key == "cold-release"), prefix: "public")

        for schema <- [Marker, Event, Webhook, SecurityEvent, RecoveryCode, Passkey, UserToken, Security, User],
            do: Repo.delete_all(schema)
      end)

      Brando.Tenant.Cache.clear()
    end)
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  defp run(call, env) do
    {output, status} =
      System.cmd("mix", ["run", "--no-start", "--no-compile", "--no-deps-check", "-e", @script],
        env: [{"MIX_ENV", "test"}, {"CALL", call} | env],
        stderr_to_stdout: true
      )

    assert status == 0, output
    output
  end

  defp user!(email) do
    Repo.insert!(%User{name: "Owner", email: email, password: "x", role: :superuser, language: :en})
  end

  # A site environment with its own webhooks
  defp site! do
    put_test_env(:tenancy_mode, :multi)

    {:ok, site} =
      Brando.Tenant.Registry.create_site(%{
        name: "Cold",
        key: "cold-release",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _} = Brando.Tenant.Registry.create_environment(site, %{name: "P", key: "production", live: true})
    Repo.query!(~s|CREATE SCHEMA "#{@prefix}"|)

    for table <- ~w(webhooks webhook_deliveries activity_events notification_routes notification_deliveries),
        do: Repo.query!(~s|CREATE TABLE "#{@prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
  end

  for {source, tenancy} <- [{"configured", "multi"}, {"secret_key_base", "none"}] do
    @tag source: source, tenancy: tenancy
    test "forget_unreadable/0 starts what it needs, with the #{source} secret, tenancy #{tenancy}", %{
      source: source,
      tenancy: tenancy
    } do
      # What this installation writes, with the secret the new VM finds
      if source == "secret_key_base", do: put_test_env(Brando.Crypto, [])

      {lost, kept, readable, hooks} =
        unboxed(fn ->
          if tenancy == "multi", do: site!()
          lost = user!("lost@example.com")
          kept = user!("kept@example.com")
          ForeignSecret.two_factor!(lost, false)
          readable = ForeignSecret.two_factor!(kept, true)
          prefixes = if tenancy == "multi", do: [nil, @prefix], else: [nil]
          {lost, kept, readable, for(prefix <- prefixes, do: {prefix, ForeignSecret.webhook!(prefix, false)})}
        end)

      output =
        run("Brando.Release.forget_unreadable()", [{"SECRET_SOURCE", source}, {"TENANCY", tenancy}])

      assert output =~ "1 users' two-factor authentication reset"
      assert output =~ "#{length(hooks)} webhooks paused"
      assert output =~ "The encryption marker is written"

      unboxed(fn ->
        assert is_nil(Repo.get_by(Security, user_id: lost.id).totp_secret)
        assert Repo.get_by(Security, user_id: kept.id).totp_secret == readable

        for {prefix, hook} <- hooks,
            do: refute(Repo.get!(Webhook, hook.id, prefix: prefix || "public").active)

        assert %{key: :ours, host: :same} = Marker.state()
      end)
    end
  end

  test "reset_two_factor/1 starts what it needs, and turns one user's two-factor authentication off" do
    owner =
      unboxed(fn ->
        owner = user!("owner@example.com")
        ForeignSecret.two_factor!(owner, true)
        Repo.insert!(%Passkey{user_id: owner.id, credential_id: "cred", cose_key: "key", name: "Laptop"})
        owner
      end)

    output = run(~S|Brando.Release.reset_two_factor("owner@example.com")|, [])

    assert output =~ "Two-factor authentication is off for owner@example.com"

    unboxed(fn ->
      assert is_nil(Repo.get_by(Security, user_id: owner.id).totp_secret)
      refute Repo.get_by(Passkey, user_id: owner.id)
      assert %SecurityEvent{actor_id: nil} = Repo.get_by(SecurityEvent, user_id: owner.id, action: :two_factor_reset)
    end)
  end
end
