if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Migration do
    @moduledoc false

    alias Brando.Blueprint.Migrations
    alias Brando.Exception.BlueprintError
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Input

    def plan(igniter) do
      options = igniter.args.options

      with {:ok, name} <- Input.required(igniter.args.positional[:blueprint], "Blueprint module", options[:interactive]),
           {:ok, name} <- Input.module_name(name, "Blueprint module"),
           module = Module.concat([name]),
           :ok <- compiled?(module),
           :ok <- accepted_source?(igniter, module),
           :ok <- single_storage_plan(igniter) do
        prepared = Migrations.plan(module, Keyword.take(options, [:migration_path, :snapshot_path, :rebaseline]))
        attach(igniter, prepared)
      else
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    rescue
      error in [BlueprintError, File.Error] -> Igniter.add_issue(igniter, Exception.message(error))
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
end
