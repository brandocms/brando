if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceTask do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # `run/1` for the `brando.migrate5x` source upgrades.
    #
    # Igniter's own `run/1` compiles the application first. The source these
    # tasks rewrite is written for the previous Brando and usually does not
    # compile against the new one, so the task would die before it rewrote
    # anything. Every rewrite reads source through Igniter, so loading the
    # dependencies and the configuration is enough.

    alias Igniter.Mix.Task.Info

    def run(task, argv) do
      if Igniter.Mix.Task.help_requested?(argv) do
        Mix.Task.run("help", [Mix.Task.task_name(task)])
      else
        if Mix.Project.umbrella?() do
          Mix.raise("Cannot run #{Mix.Task.task_name(task)} in an umbrella project.")
        end

        load_dependencies()
        Application.ensure_all_started(:rewrite)

        task_name = Mix.Task.task_name(task)
        global_options = Info.global_options()

        info =
          argv
          |> task.info(nil)
          |> Map.update!(:schema, &Keyword.merge(&1, global_options[:switches]))

        {opts, _} = Igniter.Util.Info.validate!(argv, info, task_name)

        Igniter.new()
        |> Map.put(:task, task_name)
        |> Igniter.Mix.Task.configure_and_run(task, argv)
        |> then(&Igniter.do_or_dry_run(&1, Keyword.put(opts, :yes, &1.args.options[:yes])))
      end
    end

    # Mix loads the configuration before running a task. Load the dependency
    # code paths and applications (for `Application.spec/2` and `app_dir/2`),
    # but not the application's own, possibly stale, build.
    defp load_dependencies do
      Mix.Task.run("deps.loadpaths")
      Mix.Project.deps_paths() |> Map.keys() |> Enum.each(&Application.load/1)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceTask do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
