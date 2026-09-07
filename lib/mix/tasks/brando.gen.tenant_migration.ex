if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.TenantMigration do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans an application-owned tenant migration"
    @moduledoc """
    Creates an empty migration through Igniter's reviewed source plan:

        mix brando.gen.tenant_migration add_projects
        mix brando.gen.tenant_migration --interactive

    Names use lowercase letters, digits and underscores. An existing migration
    with the same name is preserved, including its implementation and timestamp.
    Use --migrations-path for a custom project-relative directory and
    --migration-module for an explicit alternative to Ecto.Migration.
    Database application remains a separate operation.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        positional: [name: [optional: true]],
        schema:
          Mix.Brando.Igniter.Project.options() ++
            [interactive: :boolean, migrations_path: :string, migration_module: :string]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.TenantMigration.plan(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen.TenantMigration do
    use Mix.Task

    @doc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans a tenant migration (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.tenant_migration")
  end
end
