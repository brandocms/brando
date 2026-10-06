defmodule Mix.Tasks.Brando.Identifiers.Sync do
  @shortdoc "Clean up, update existing and recreate missing identifiers"

  @moduledoc """
  This task will clean up, update existing and recreate missing identifiers.

  An entry that raises is skipped and listed at the end, and the task then
  exits with status 1.
  """
  use Mix.Task

  @spec run(any) :: no_return
  def run([]) do
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

      {:error, failures} ->
        Mix.shell().error("\n==> Done, but #{length(failures)} identifier(s) failed. See above.\n")
        exit({:shutdown, 1})
    end
  end
end
