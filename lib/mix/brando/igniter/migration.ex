if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Migration do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Brando.Blueprint.Migrations
    alias Brando.Exception.BlueprintError
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Input
    alias Mix.Brando.Igniter.Install.Configuration

    def plan(igniter) do
      options = igniter.args.options

      with {:ok, name} <- Input.required(igniter.args.positional[:blueprint], "Blueprint module", options[:interactive]),
           {:ok, name} <- Input.module_name(name, "Blueprint module"),
           module = Module.concat([name]),
           :ok <- compiled?(module),
           :ok <- accepted_source?(igniter, module),
           :ok <- single_storage_plan(igniter),
           {:ok, igniter, options} <- storage_options(igniter, module, options) do
        prepared = Migrations.plan(module, options)
        attach(igniter, prepared)
      else
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    rescue
      error in [BlueprintError, File.Error] -> Igniter.add_issue(igniter, Exception.message(error))
    end

    defp storage_options(igniter, module, options) do
      options = Keyword.take(options, [:migration_path, :snapshot_path, :rebaseline])

      if options[:migration_path] do
        {:ok, igniter, options}
      else
        with {:ok, igniter, mode} <- Configuration.read(igniter, :tenancy_mode),
             {:ok, path} <- default_migration_path(module, mode) do
          {:ok, igniter, Keyword.put(options, :migration_path, path)}
        end
      end
    end

    defp default_migration_path(module, mode) when mode in [nil, :none, :single, :multi] do
      case module.__schema__(:prefix) do
        prefix when prefix in [nil, "public"] ->
          conventional_migration_path(module, mode)

        prefix ->
          {:error,
           "#{inspect(module)} fixes its schema prefix to #{inspect(prefix)}. Choose --migration-path explicitly and apply those migrations with the matching Ecto --prefix; a public or tenant destination cannot be inferred."}
      end
    end

    defp default_migration_path(_module, mode), do: {:error, "Unsupported configured tenancy mode #{inspect(mode)}."}

    defp conventional_migration_path(module, mode) do
      paths = {"priv/repo/migrations", "priv/repo/tenant_migrations"}
      tenant? = mode in [:single, :multi] && is_nil(module.__schema__(:prefix))
      {selected, other} = if tenant?, do: {elem(paths, 1), elem(paths, 0)}, else: paths

      if Migrations.migration_files(module, migration_path: other) == [] do
        {:ok, selected}
      else
        {:error,
         "#{inspect(module)} already has storage history in #{other}. Choose --migration-path explicitly after reviewing the tenancy transition; changing source configuration does not migrate existing tables between schemas."}
      end
    end

    defp compiled?(module) do
      if Code.ensure_loaded?(module) && function_exported?(module, :__blueprint__, 0),
        do: :ok,
        else:
          {:error, "#{inspect(module)} is not a compiled Brando Blueprint. Accept its source and run mix compile first."}
    end

    defp accepted_source?(igniter, module) do
      case ProjectModule.find_module(igniter, module) do
        {:ok, {_, source, _}} ->
          if source.from != :file || Rewrite.Source.updated?(source, :content),
            do:
              {:error,
               "#{inspect(module)} has pending changes. Accept and compile the Blueprint before planning storage."},
            else: :ok

        {:error, _} ->
          :ok
      end
    end

    defp single_storage_plan(igniter) do
      if igniter.assigns[:brando_storage_plan],
        do:
          {:error,
           "Compose one Blueprint storage plan per invocation. Commit it before planning the next Blueprint so migration ordering and history checks stay valid."},
        else: :ok
    end

    defp attach(igniter, %{result: :noop, snapshot: nil} = plan) do
      Igniter.add_notice(igniter, "No storage changes necessary for #{inspect(plan.module)}.")
    end

    defp attach(igniter, plan) do
      # A snapshot is binary and its migration is one transaction participant.
      # Display the exact source now, before Igniter's acceptance prompt, and
      # defer both writes to the checked storage writer instead of Rewrite.
      Mix.shell().info(preview(plan))
      request = Mix.Brando.MigrationRequest.encode(plan)

      igniter
      |> Igniter.assign(:brando_storage_plan, plan)
      |> Igniter.assign(:quiet_on_no_changes?, true)
      |> Igniter.add_task("brando.blueprint.apply_plan", [request])
    end

    defp preview(plan) do
      migration =
        if plan.migration_source,
          do: "Migration: #{plan.metadata.migration}\n\n#{plan.migration_source}\n",
          else: "No migration file.\n"

      snapshot = snapshot_path(plan)

      schema =
        if plan.snapshot.rebaseline?,
          do: "\nStorage schema:\n#{inspect(plan.snapshot.schema, pretty: true, limit: :infinity)}\n",
          else: ""

      """
      Blueprint storage plan for #{inspect(plan.module)}
      #{migration}
      Snapshot: #{snapshot} (version #{plan.metadata.snapshot_version}, format #{plan.snapshot.format_version})
      Rebaseline: #{plan.snapshot.rebaseline?}
      #{schema}
      Both files will be persisted together only after acceptance and a fresh history/schema check.
      """
    end

    defp snapshot_path(plan) do
      plan.metadata[:snapshot] ||
        Path.join(
          Brando.Blueprint.Snapshot.build_path(plan.module, plan.options),
          "#{String.pad_leading(to_string(plan.snapshot.version), 3, "0")}.snapshot"
        )
    end
  end
else
  defmodule Mix.Brando.Igniter.Migration do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
