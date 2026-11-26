defmodule Brando.ReleaseTest do
  # Brando.Release runs in `bin/my_app eval`: a new VM with nothing started.
  # Each test runs it in one, `mix run --no-start`, with the test build and
  # configuration. The endpoint module is defined there, as in a release, but
  # never started. The script keeps what it writes in a sandbox transaction
  # that ends with it; the repo is started first only to hold that sandbox.
  use ExUnit.Case, async: true

  @moduletag timeout: 180_000

  @prelude ~S"""
  defmodule BrandoIntegrationWeb.Endpoint do
    use Phoenix.Endpoint, otp_app: :brando
  end

  alias Brando.Test.ForeignSecret

  repo = BrandoIntegration.Repo
  # Nothing is started: not the repo, Brando's processes, PubSub, the
  # endpoint, or plug_crypto's key cache
  nil = Process.whereis(repo)
  nil = Process.whereis(Brando.Supervisor)
  nil = Process.whereis(BrandoIntegration.PubSub)
  nil = Process.whereis(BrandoIntegrationWeb.Endpoint)

  case System.get_env("SECRET_SOURCE") do
    "secret_key_base" -> Application.delete_env(:brando, Brando.Crypto)
    "configured" -> :ok
  end

  {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
  {:ok, _apps} = Application.ensure_all_started(:postgrex)
  {:ok, _pid} = repo.start_link(pool_size: 1)
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)
  Logger.configure(level: :warning)

  # On an empty database first: it starts the rest of what it needs itself
  :undefined = :ets.whereis(Plug.Crypto.Keys)
  %{users: 0, failed: [], marker: :written} = Brando.Release.forget_unreadable()

  user = fn email ->
    repo.insert!(%Brando.Users.User{name: "Owner", email: email, password: "x", role: :superuser, language: :en})
  end
  """

  defp run(script, source) do
    {output, status} =
      System.cmd("mix", ["run", "--no-start", "--no-compile", "--no-deps-check", "-e", @prelude <> script],
        env: [{"MIX_ENV", "test"}, {"SECRET_SOURCE", source}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    output
  end

  for source <- ["configured", "secret_key_base"] do
    @tag source: source
    test "forget_unreadable/0 forgets what this secret cannot read, with the #{source} secret", %{source: source} do
      output =
        run(
          ~S"""
          lost = user.("lost@example.com")
          kept = user.("kept@example.com")
          ForeignSecret.two_factor!(lost, false)
          readable = ForeignSecret.two_factor!(kept, true)
          hook = ForeignSecret.webhook!(nil, false)

          %{users: 1, webhooks: 1, failed: [], marker: :written} = Brando.Release.forget_unreadable()

          nil = repo.get_by(Brando.Users.Security, user_id: lost.id).totp_secret
          ^readable = repo.get_by(Brando.Users.Security, user_id: kept.id).totp_secret
          false = repo.get!(Brando.Webhooks.Webhook, hook.id).active
          %{key: :ours} = Brando.Crypto.Marker.state()
          nil = Process.whereis(BrandoIntegrationWeb.Endpoint)
          IO.puts("checked")
          """,
          source
        )

      assert output =~ "1 users' two-factor authentication reset"
      assert output =~ "1 webhooks paused"
      assert output =~ "The encryption marker is written"
      assert output =~ "checked"
    end
  end

  test "reset_two_factor/1 turns two-factor authentication off for one user, passkeys included" do
    output =
      run(
        ~S"""
        owner = user.("owner@example.com")
        ForeignSecret.two_factor!(owner, true)

        repo.insert!(%Brando.Users.Passkey{
          user_id: owner.id,
          credential_id: "cred",
          cose_key: "key",
          name: "Laptop"
        })

        {:ok, _user} = Brando.Release.reset_two_factor(" owner@example.com ")
        nil = repo.get_by(Brando.Users.Security, user_id: owner.id).totp_secret
        nil = repo.get_by(Brando.Users.Passkey, user_id: owner.id)

        %Brando.Users.SecurityEvent{actor_id: nil} =
          repo.get_by(Brando.Users.SecurityEvent, user_id: owner.id, action: :two_factor_reset)

        {:error, :not_found} = Brando.Release.reset_two_factor("nobody@example.com")
        IO.puts("checked")
        """,
        "configured"
      )

    assert output =~ "Two-factor authentication is off for owner@example.com"
    assert output =~ "No user has the email nobody@example.com"
    assert output =~ "checked"
  end
end
