defmodule Mix.Tasks.Brando.Identifiers.Sync do
  @shortdoc "Clean up, update existing and recreate missing identifiers"

  @moduledoc """
  This task will clean up, update existing and recreate missing identifiers.
  """
  use Mix.Task

  @spec run(any) :: no_return
  def run([]) do
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    -------------------------
    % Brando Sync Identifiers
    -------------------------
    """)

    Brando.Blueprint.Identifier.sync()

    Mix.shell().info([:green, "\n==> Done.\n"])
  end
end
