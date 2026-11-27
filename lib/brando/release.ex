defmodule Brando.Release do
  @moduledoc """
  Functions for whoever runs the server, on a release with `bin/my_app eval`
  or in development with `mix run -e`. Nothing needs adding to the
  project's own `ReleaseTasks`:

      bin/my_app eval "Brando.Release.forget_unreadable()"
      bin/my_app eval 'Brando.Release.reset_two_factor("admin@example.com")'

      mix run -e "Brando.Release.forget_unreadable()"

  `eval` runs in a new VM with nothing started. `forget_unreadable/0` and
  `reset_two_factor/1` start the repo and the PubSub server they need, and
  not the endpoint or Oban: the
  encryption secret is read from the configuration, also when it is the
  endpoint's `secret_key_base`. Without the endpoint, the security emails
  are not sent and other nodes' open admin tabs are not told; the sessions
  end all the same. Each prints what it did. See "Copying a database between
  environments" in the deployment guide.

  `refresh_bunny_videos/0` runs best on the serving node, which then tells
  the open admin tabs and empties its caches:

      bin/my_app rpc "Brando.Release.refresh_bunny_videos()"

  With `eval` it starts the application in its VM as
  `Brando.Content.Resave.run/1` does, without the web server or Oban's
  queues: the entries showing a changed video render on the server's queues.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Crypto.Audit
  alias Brando.Users.TwoFactor
  alias Brando.Users.User
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Video

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

  @doc """
  Runs **Fetch details** (`Brando.Videos.Uploaders.Bunny.refresh_renditions/2`)
  for every ready Bunny video, deleted ones excepted, one request at a time:
  each gets its renditions and the name of its thumbnail, which changes when
  a custom thumbnail is set in Bunny. With tenancy, in `public` and every
  environment of every site. A video Bunny does not answer for (an error, a
  rate limit, a timeout) is counted and the rest go on; nothing is retried,
  so run it again for those. Only a video that changed is written, as
  **Fetch details** writes it: the entries showing it render again, and open
  admin forms showing it are told.

  Returns `%{refreshed: n, unchanged: n, failed: [{schema, id}]}`, the schema
  `"public"` or an environment's prefix; `{:error, :not_configured}` without
  Bunny credentials, or `{:error, message}` when the application cannot be
  started (see `Brando.Content.Resave.run/1`).
  """
  @spec refresh_bunny_videos() :: map() | {:error, :not_configured | String.t()}
  def refresh_bunny_videos do
    with true <- Bunny.configured?() || {:error, :not_configured},
         {:ok, _started_here?} <- Brando.Content.Resave.start(Brando.otp_app()) do
      result =
        Enum.reduce(Audit.prefixes(), %{refreshed: 0, unchanged: 0, failed: []}, &refresh_bunny_videos_in/2)

      result = %{result | failed: Enum.reverse(result.failed)}
      IO.puts(describe_bunny(result))
      result
    else
      {:error, :not_configured} = error ->
        IO.puts("Bunny is not configured: no video was refreshed.")
        error

      {:error, message} = error ->
        IO.puts("Nothing was done: " <> message)
        error
    end
  end

  defp refresh_bunny_videos_in(prefix, acc) do
    in_schema(prefix, fn -> Enum.reduce(bunny_video_ids(), acc, &refresh_bunny_video(&1, &2, prefix)) end)
  end

  defp in_schema(nil, fun), do: Brando.Tenant.with_public(fun)
  defp in_schema(prefix, fun), do: Brando.Tenant.with_prefix(prefix, fun)

  defp bunny_video_ids do
    Brando.Repo.all(from(v in ready_bunny_videos(), select: v.id, order_by: v.id))
  end

  # A video still encoding has nothing to refresh, and its webhook writes
  # its details
  defp ready_bunny_videos do
    from(v in Video,
      where: v.type == :bunny and v.status == :ready and is_nil(v.deleted_at),
      where: not is_nil(fragment("?->'bunny'->>'video_guid'", v.meta))
    )
  end

  # Loaded just before its request, so a webhook's write while earlier
  # videos were looked up is kept
  defp refresh_bunny_video(id, acc, prefix) do
    case Brando.Repo.one(from(v in ready_bunny_videos(), where: v.id == ^id)) do
      nil -> acc
      video -> count_bunny_refresh(video, Bunny.refresh_renditions(video, :system, retry: false), acc, prefix)
    end
  end

  defp count_bunny_refresh(video, {:ok, %Video{meta: meta}}, acc, _prefix) when meta == video.meta,
    do: %{acc | unchanged: acc.unchanged + 1}

  defp count_bunny_refresh(_video, {:ok, _refreshed}, acc, _prefix), do: %{acc | refreshed: acc.refreshed + 1}

  defp count_bunny_refresh(video, {:error, _reason}, acc, prefix),
    do: %{acc | failed: [{prefix || "public", video.id} | acc.failed]}

  defp describe_bunny(%{refreshed: refreshed, unchanged: unchanged, failed: failed}) do
    failed_line =
      case failed do
        [] ->
          []

        failed ->
          ids = Enum.map_join(failed, ", ", fn {schema, id} -> "##{id} in #{schema}" end)
          ["  #{length(failed)} failed (see the log): #{ids}. Run it again for them."]
      end

    Enum.join(
      ["Refreshed the Bunny videos:", "  #{refreshed} refreshed", "  #{unchanged} unchanged" | failed_line],
      "\n"
    )
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
