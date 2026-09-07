defmodule Mix.Tasks.Brando.Install.Fabfile do
  use Mix.Task

  @shortdoc "Retired Fabric scaffold; use brando.gen.release and Florist"
  @moduledoc """
  The legacy Fabric/pgbackup scaffold is retired. Generate release helpers with
  `mix brando.gen.release`, then configure deployment using the Florist guide.
  Existing Fabric configuration is preserved. See `guides/deployment.md` for the
  supported deployment workflow and migration from existing configuration.
  """

  @impl Mix.Task
  def run(_argv) do
    Mix.raise(
      "brando.install.fabfile is retired. Use mix brando.gen.release and the Florist deployment guide (guides/deployment.md). Existing deployment files were preserved."
    )
  end
end
