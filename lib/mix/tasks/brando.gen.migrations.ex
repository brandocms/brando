if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Migrations do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans missing framework migration files"
    @moduledoc """
    Copies missing versioned Brando migrations and tenant migration templates through
    a reviewed Igniter plan. Historical files and timestamps are preserved.
    This does not recreate the pre-versioned baseline tables or run the database.

        mix brando.gen.migrations

    Apply public migrations with mix brando.migrate, then named environments with
    mix brando.migrate --tenants. For initial installation use brando.install.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Upgrade.migrations(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Migrations do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans missing framework migration files (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.migrations")
  end
end
