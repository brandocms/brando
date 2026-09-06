if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Upgrade do
    @moduledoc false

    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Install.Migrations
    alias Mix.Brando.Igniter.Project

    @legacy_module Mix.Tasks.Brando.Upgrade
    @archive "priv/brando/legacy_tasks/brando.upgrade.ex.disabled"
    @minimum "0.54.0-dev"

    # A separate task must remove the consumer module before the next Mix process
    # can resolve the library-owned brando.upgrade task. Never replace a loaded
    # task module or silently discard a consumer's customized upgrade logic.
    def prepare(igniter) do
      case ProjectModule.find_module(igniter, @legacy_module) do
        {:error, igniter} ->
          Igniter.add_notice(
            igniter,
            "No consumer-owned brando.upgrade task was found. Use mix brando.gen.migrations to plan framework migrations."
          )

        {:ok, {igniter, source, _}} ->
          retire(igniter, source)
      end
    end

    defp retire(igniter, source) do
      contents = Rewrite.Source.get(source, :content)
      template = Application.app_dir(:brando, "priv/templates/brando.install/lib/mix/brando.upgrade.ex")

      if normalized(contents) == normalized(File.read!(template)) do
        igniter = Files.create(igniter, @archive, contents)

        if igniter.issues == [] do
          igniter
          |> Igniter.rm(source.path)
          |> Igniter.add_notice("""
          Archived the recognized legacy task at #{@archive}.
          After accepting, run mix compile in a new invocation to remove its stale beam.
          Use mix brando.gen.migrations for framework migration files, or
          mix igniter.upgrade brando for versioned package upgrades.
          """)
        else
          igniter
        end
      else
        Igniter.add_issue(igniter, """
        #{source.path} defines a customized or unrecognized Mix.Tasks.Brando.Upgrade.
        Rename its module and task (for example MyApp.Upgrade), preserving your logic,
        then compile before using Igniter upgrades. No legacy task was removed.
        """)
      end
    end

    defp normalized(contents), do: contents |> Sourceror.parse_string!() |> Sourceror.strip_meta()

    def migrations(igniter) do
      with {:ok, igniter, options} <- Configuration.namespace_options(igniter, igniter.args.options),
           {:ok, igniter, project} <- Project.discover(igniter, options) do
        igniter
        |> Migrations.plan(project, upgrade: true)
        |> Igniter.add_notice("""
        Review and accept missing framework migrations, then run mix compile.
        Apply public migrations explicitly with mix brando.migrate.
        For named environments, follow with mix brando.migrate --tenants.
        Historical migration files and timestamps are preserved; no database operations were scheduled.
        """)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    def plan(igniter) do
      from = igniter.args.positional[:from]
      to = igniter.args.positional[:to]

      with {:ok, from_version} <- version(from),
           {:ok, to_version} <- version(to),
           :ok <- supported(from_version, to_version) do
        case ProjectModule.find_module(igniter, @legacy_module) do
          {:ok, {igniter, source, _}} ->
            Igniter.add_issue(
              igniter,
              "#{source.path} still owns brando.upgrade. Run mix brando.upgrade.prepare and compile before upgrading."
            )

          {:error, igniter} ->
            apply_version(igniter, from_version, to_version)
        end
      else
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp apply_version(igniter, from, to) do
      if Version.compare(from, to) == :eq do
        Igniter.add_notice(
          igniter,
          "Brando is already at #{to}; use mix brando.gen.migrations to reconcile missing framework migration files."
        )
      else
        migrations(igniter)
      end
    end

    defp version(value) when is_binary(value) do
      case Version.parse(value) do
        {:ok, version} -> {:ok, version}
        :error -> {:error, "Expected semantic versions: mix brando.upgrade FROM TO; got #{inspect(value)}."}
      end
    end

    defp version(_),
      do:
        {:error,
         "Use mix brando.gen.migrations to copy missing framework migrations. Versioned upgrades require FROM TO arguments."}

    defp supported(from, to) do
      installed = Application.spec(:brando, :vsn) |> to_string() |> Version.parse!()

      cond do
        Version.compare(from, to) == :gt ->
          {:error,
           "Brando source downgrades are not supported. Restore the intended dependency and source revision explicitly."}

        Version.compare(to, installed) == :gt ->
          {:error,
           "The loaded Brando version is #{installed}; cannot apply source upgrades for #{to}. Update the dependency first."}

        Version.compare(from, @minimum) == :lt ->
          {:error,
           "Before upgrading from #{from}, follow guides/migrating_to_054.md and run mix brando.migrate54. The automatic hook supports #{@minimum} and newer."}

        to.major != 0 or to.minor != 54 ->
          {:error,
           "This upgrade recipe covers the 0.54 development line. #{to} requires a version-specific source upgrade recipe."}

        true ->
          :ok
      end
    end
  end
end
