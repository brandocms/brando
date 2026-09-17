defmodule Mix.Tasks.Brando.Gen.Seeds do
  use Mix.Task

  @shortdoc "Seed default content for a new installation"

  @moduledoc """
  Seed default content for a new installation.

      mix brando.gen.seeds
      mix brando.gen.seeds --user 1

  Creates identity and SEO defaults per configured language, a small set of
  content modules, a published `index` page built from them, a main navigation
  menu and a footer fragment. Existing content of each kind is left alone, so
  the task is safe to rerun.

  The seeded content is a starting point for editing in the admin, not a
  migration or an upgrade path.

  Requires an account to own the content. Without `--user ID` the oldest
  superuser is used. Create one with `mix brando.gen.admin`.
  """

  @switches [user: :integer]

  @impl Mix.Task
  @spec run([binary]) :: :ok
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)

    Application.put_env(:logger, :level, :error)
    Mix.Task.run("app.start")

    user = user!(opts[:user])

    Mix.shell().info("""

    ---------------------------
    % Brando Seed Content
    ---------------------------
    """)

    {:ok, report} = Brando.Setup.Seeds.run(user)

    for label <- Enum.reverse(report.created), do: Mix.shell().info([:green, "    + #{label}"])
    for label <- Enum.reverse(report.skipped), do: Mix.shell().info([:yellow, "    = #{label} (exists)"])

    Mix.shell().info([:green, "\n==> Done.\n"])
  end

  defp user!(nil) do
    case Brando.Setup.Account.superuser() do
      nil ->
        Mix.raise("""
        No active superuser found. Seeded content needs an account to own it.

            mix brando.gen.admin
        """)

      user ->
        user
    end
  end

  defp user!(id) do
    case Brando.Repo.get(Brando.Users.User, id) do
      nil -> Mix.raise("--user #{id} does not identify an account.")
      %{active: false} -> Mix.raise("--user #{id} is not active.")
      %{deleted_at: deleted_at} when not is_nil(deleted_at) -> Mix.raise("--user #{id} is deleted.")
      user -> user
    end
  end
end
