defmodule Mix.Tasks.Brando.Gen.TenantMigration do
  @shortdoc "Generates an application-owned tenant migration"

  @moduledoc """
  Generates an Ecto migration under `priv/repo/tenant_migrations`:

      mix brando.gen.tenant_migration add_projects

  Use `--migrations-path` for an umbrella or custom repository layout.
  """

  use Mix.Task

  import Mix.Generator, only: [create_file: 2]

  @switches [migrations_path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")

    case positional do
      [name] ->
        path = opts[:migrations_path] || "priv/repo/tenant_migrations"
        generate!(name, path)

      _ ->
        Mix.raise("Usage: mix brando.gen.tenant_migration migration_name")
    end
  end

  defp generate!(name, path) do
    unless Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_]*$/, name) do
      Mix.raise("Migration name must contain only letters, numbers, and underscores")
    end

    underscored_name = Macro.underscore(name)
    existing = Path.wildcard(Path.join(path, "*_#{underscored_name}.exs"))

    if existing != [] do
      Mix.raise("A tenant migration named #{name} already exists")
    end

    repo = Mix.Ecto.parse_repo([]) |> List.first()
    module = Module.concat([repo, Migrations, Macro.camelize(name)])
    migration_module = Application.get_env(:ecto_sql, :migration_module, Ecto.Migration)
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    file = Path.join(path, "#{timestamp}_#{underscored_name}.exs")

    create_file(file, """
    defmodule #{inspect(module)} do
      use #{inspect(migration_module)}

      def change do
      end
    end
    """)

    file
  end
end
