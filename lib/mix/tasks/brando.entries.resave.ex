defmodule Mix.Tasks.Brando.Entries.Resave do
  use Mix.Task

  @shortdoc "Re-save all entries"

  @moduledoc """
  Re-save all entries

      mix brando.entries.resave
      mix brando.entries.resave --yes

  Re-save entries for specific blueprint

      mix brando.entries.resave MyApp.Projects.Project

  Options:

    * `--yes` (or `--force`) - Skip the confirmation prompt. Without it and
      without a terminal to answer on, the task does nothing and exits
      non-zero.
    * `--site <key>` - With tenancy, only this site's environments.
    * `--environment <key>` - With tenancy, only the environment with this
      key, in each site (or in `--site`'s).

  With tenancy (`:single` or `:multi`), the entries are in each environment's
  schema: the task re-saves them in every environment of every site, each
  under its own prefix and outside any admin scope, and names each
  environment as it goes. Without tenancy it re-saves the entries in the
  application's own tables.

  A server that is already running keeps serving the pages it cached before
  (pages are cached without expiry): restart it, or use Configuration →
  Utilities → Clear caches in its admin. The task says so when it is done.

  A release has no Mix: there, `bin/my_app rpc "Brando.Content.Resave.run()"`
  does the same on the running node (as does `MyApp.ReleaseTasks.resave_entries/1`
  where `ReleaseTasks` has it), and empties that node's query cache itself.
  See "Data tasks in a release" in the deployment guide.
  """

  @spec run(any) :: no_return
  def run(args) do
    {opts, rest} =
      Mix.Brando.parse_options!(
        "brando.entries.resave",
        args,
        [yes: :boolean, force: :boolean, site: :string, environment: :string],
        aliases: [y: :yes],
        max_positional: 1
      )

    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ------------------------------
    % Brando Resave Entries
    ------------------------------
    """)

    resave_opts = [
      blueprint: List.first(rest),
      site: opts[:site],
      environment: opts[:environment],
      # The task's own node holds no server's caches
      reload_caches: false,
      info: fn line -> Mix.shell().info(line) end,
      confirm: fn _plan -> Mix.Brando.confirm?("\n\nProceed?", opts) end
    ]

    case Brando.Content.Resave.run(resave_opts) do
      {:ok, _count_or_declined} -> :ok
      {:error, message} -> Mix.raise("mix brando.entries.resave: " <> message)
    end
  end
end
