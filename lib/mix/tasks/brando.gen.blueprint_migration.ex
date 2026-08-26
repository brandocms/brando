defmodule Mix.Tasks.Brando.Gen.BlueprintMigration do
  use Mix.Task

  @shortdoc "Generates a reversible migration from a Blueprint storage diff"

  @moduledoc """
  Generates the next reviewed Ecto migration and versioned storage snapshot for
  a Blueprint.

      mix brando.gen.blueprint_migration MyApp.Projects.Project

  Use `--rebaseline` only after a hand-written migration has brought the database
  in line with the current Blueprint:

      mix brando.gen.blueprint_migration MyApp.Projects.Project --rebaseline

  Custom paths are useful in umbrella applications and tests:

      mix brando.gen.blueprint_migration MyApp.Projects.Project \\
        --migration-path apps/my_app/priv/repo/migrations \\
        --snapshot-path apps/my_app/priv/blueprints/snapshots
  """

  @switches [
    migration_path: :string,
    rebaseline: :boolean,
    snapshot_path: :string
  ]

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    module = parse_module!(positional)
    ensure_blueprint!(module)

    result =
      if opts[:rebaseline] do
        Brando.Blueprint.Migrations.rebaseline_snapshot(module, opts)
      else
        Brando.Blueprint.Migrations.create_migration(module, opts)
      end

    report(result)
  end

  defp parse_module!([module_name]), do: Module.concat([module_name])

  defp parse_module!(_) do
    Mix.raise("Usage: mix brando.gen.blueprint_migration MyApp.Domain.Schema [options]")
  end

  defp ensure_blueprint!(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :__blueprint__, 0) do
      Mix.raise("#{inspect(module)} is not a compiled Brando Blueprint")
    end
  end

  defp report({:noop, metadata}) do
    Mix.shell().info([:green, "No migration needed for #{inspect(metadata.module)}."])
  end

  defp report({:ok, %{migration: migration} = metadata}) do
    Mix.shell().info([:green, "Created #{migration}"])
    Mix.shell().info([:green, "Created #{metadata.snapshot}"])

    if metadata.destructive_operations != [] do
      Mix.shell().error(
        "Review destructive operations before running the migration: #{inspect(metadata.destructive_operations)}"
      )
    end
  end

  defp report({:ok, metadata}) do
    Mix.shell().info([:yellow, "Re-baselined #{inspect(metadata.module)} at #{metadata.snapshot}"])
  end
end
