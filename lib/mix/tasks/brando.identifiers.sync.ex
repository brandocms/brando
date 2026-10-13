defmodule Mix.Tasks.Brando.Identifiers.Sync do
  @shortdoc "Clean up, update existing and recreate missing identifiers"

  @moduledoc """
  This task will clean up, update existing and recreate missing identifiers.

      mix brando.identifiers.sync
      mix brando.identifiers.sync --yes

  It asks nothing, so `--yes` (or `--force`) is accepted and ignored: the
  derived-data tasks (`brando.entries.resave`, `brando.identifiers.sync`,
  `brando.images.adopt`) all take it. Any other option stops the task.

  An entry that raises is skipped and listed at the end, and the task then
  exits with status 1.

  A server that is already running keeps serving what it cached before:
  restart it, or use Configuration → Cache → Empty all caches in its admin.
  The task says so when it is done.
  """
  use Mix.Task

  @switches [yes: :boolean, force: :boolean]

  @spec run(any) :: no_return
  def run(args) do
    Mix.Brando.parse_options!("brando.identifiers.sync", args, @switches, aliases: [y: :yes])

    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    -------------------------
    % Brando Sync Identifiers
    -------------------------
    """)

    case Brando.Blueprint.Identifier.sync() do
      :ok ->
        Mix.shell().info([:green, "\n==> Done.\n"])
        Mix.Brando.running_server_note()

      {:error, failures} ->
        Mix.shell().error("\n==> Done, but #{length(failures)} identifier(s) failed. See above.\n")
        Mix.Brando.running_server_note()
        exit({:shutdown, 1})
    end
  end
end
