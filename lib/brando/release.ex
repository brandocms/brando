defmodule Brando.Release do
  @moduledoc """
  Functions for whoever runs the server, on a release with `bin/my_app eval`
  or in development with `mix run -e`. Nothing needs adding to the
  project's own `ReleaseTasks`:

      bin/my_app eval "Brando.Release.forget_unreadable()"
      bin/my_app eval 'Brando.Release.reset_two_factor("admin@example.com")'

      mix run -e "Brando.Release.forget_unreadable()"

  `eval` runs in a new VM with nothing started. Each function starts the
  repo and the PubSub server it needs, and not the endpoint or Oban: the
  encryption secret is read from the configuration, also when it is the
  endpoint's `secret_key_base`. Without the endpoint, the security emails
  are not sent and other nodes' open admin tabs are not told; the sessions
  end all the same. Each prints what it did. See "Copying a database between
  environments" in the deployment guide.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Crypto.Audit
  alias Brando.Users.TwoFactor
  alias Brando.Users.User

  @doc """
  Forgets what this installation's encryption secret cannot read
  (`Brando.Crypto.Audit.forget/2`, as the system): unreadable two-factor
  secrets with their recovery codes, the webhooks and routes it cannot read
  (paused), Figma credentials it cannot read. Then writes the marker.
  """
  @spec forget_unreadable() :: map()
  def forget_unreadable do
    started(fn ->
      {:ok, result} = Audit.forget(:system)
      IO.puts(describe(result))
      result
    end)
  end

  @doc """
  Turns two-factor authentication off for the user with `email`, as
  `Brando.Users.TwoFactor.reset/3` does for an administrator: the app's
  secret, the passkeys and the recovery codes go, a lockout ends and every
  session ends. They sign in with their password and set it up again where
  the sign-in policy requires it. Recorded in their security log as done by
  the system. Returns `{:ok, user}` or `{:error, :not_found}`.
  """
  @spec reset_two_factor(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def reset_two_factor(email) when is_binary(email) do
    started(fn ->
      email = String.trim(email)

      with %User{id: id} <- Brando.Repo.one(from(u in User, where: u.email == ^email)) || {:error, :not_found},
           {:ok, user} <- TwoFactor.reset(id, :system) do
        IO.puts("Two-factor authentication is off for #{user.email}: they sign in with their password.")
        {:ok, user}
      else
        {:error, :not_found} = error ->
          IO.puts("No user has the email #{email}.")
          error
      end
    end)
  end

  @descriptions [
    users: "users' two-factor authentication reset",
    webhooks: "webhooks paused",
    notification_routes: "notification routes paused",
    figma_token: "Figma tokens removed",
    figma_app: "Figma apps removed",
    figma_connection: "Figma connections removed",
    figma_pending: "Figma connections being made removed"
  ]

  @doc false
  def describe(result) do
    lines = for {kind, label} <- @descriptions, do: "  #{Map.fetch!(result, kind)} #{label}"

    marker =
      case result.failed do
        [] -> "The encryption marker is written: this database is now this installation's."
        failed -> "Not finished: #{Enum.map_join(failed, ", ", &to_string/1)} failed (see the log). Run it again."
      end

    Enum.join(["Forgot what this installation's encryption secret cannot read:" | lines] ++ [marker], "\n")
  end

  # The repo and the PubSub server, when they are not running already (in
  # `mix run`, or over rpc on the serving node)
  defp started(fun) do
    :ok = load()
    # Brando.Crypto's key cache
    {:ok, _apps} = Application.ensure_all_started(:plug_crypto)
    repo = Brando.Repo.repo()

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        ensure_pubsub()
        fun.()
      end)

    result
  end

  defp load do
    for app <- [:brando, Application.get_env(:brando, :otp_app)], app do
      case Application.load(app) do
        :ok -> :ok
        {:error, {:already_loaded, _}} -> :ok
      end
    end

    :ok
  end

  defp ensure_pubsub do
    name = Brando.pubsub()

    unless Process.whereis(name) do
      {:ok, _apps} = Application.ensure_all_started(:phoenix_pubsub)
      {:ok, _pid} = Supervisor.start_link([{Phoenix.PubSub, name: name}], strategy: :one_for_one)
    end
  end
end
