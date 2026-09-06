if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.TenantMigration do
    @moduledoc false

    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Input
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Project

    def plan(igniter) do
      options = igniter.args.options

      with {:ok, name} <- Input.required(igniter.args.positional[:name], "Migration name", options[:interactive]),
           {:ok, name} <- Input.identifier(name, "Migration name"),
           {:ok, path} <- path(options[:migrations_path] || "priv/repo/tenant_migrations"),
           {:ok, migration} <- Input.module_name(options[:migration_module] || "Ecto.Migration", "Migration module"),
           {:ok, igniter, options} <- Configuration.namespace_options(igniter, options),
           {:ok, igniter, project} <- Project.discover(igniter, options) do
        generate(igniter, project, name, path, migration)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp path(value) do
      if Path.type(value) == :relative &&
           Enum.all?(Path.split(value), &Regex.match?(~r/^[a-zA-Z0-9_-]+$/, &1)) do
        {:ok, value}
      else
        {:error, "--migrations-path must be a relative directory inside the project without glob characters."}
      end
    end

    defp generate(igniter, project, name, path, migration) do
      igniter = Igniter.include_glob(igniter, Path.join(path, "*.exs"))
      files = Enum.filter(Map.keys(igniter.rewrite.sources), &(Path.dirname(&1) == path))
      existing = Enum.filter(files, &String.ends_with?(&1, "_#{name}.exs"))

      case existing do
        [] ->
          latest = files |> Enum.map(&version/1) |> Enum.max(fn -> 0 end)
          now = DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S") |> String.to_integer()
          module = Module.concat([project.repo, Migrations, Macro.camelize(name)])

          igniter
          |> Files.create(Path.join(path, "#{max(now, latest + 1)}_#{name}.exs"), """
          defmodule #{inspect(module)} do
            use #{migration}

            def change do
            end
          end
          """)
          |> Igniter.add_notice("Review the tenant migration and apply it explicitly with mix brando.migrate --tenants.")

        [file] ->
          Igniter.add_notice(igniter, "Tenant migration #{file} already exists; its implementation is preserved.")

        _ ->
          Igniter.add_issue(igniter, "Multiple tenant migrations are named #{name}. Reconcile them before continuing.")
      end
    end

    defp version(path) do
      case Integer.parse(Path.basename(path)) do
        {value, "_" <> _} -> value
        _ -> 0
      end
    end
  end
end
