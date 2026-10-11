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
    alias Mix.Task, as: MixTask

    def run(task, argv) do
      if Igniter.Mix.Task.help_requested?(argv) do
        MixTask.run("help", [MixTask.task_name(task)])
      else
        if Mix.Project.umbrella?() do
          Mix.raise("Cannot run #{MixTask.task_name(task)} in an umbrella project.")
        end

        load_dependencies()
        Application.ensure_all_started(:rewrite)

        task_name = MixTask.task_name(task)
        global_options = Info.global_options()

        info =
          argv
          |> task.info(nil)
          |> Map.update!(:schema, &Keyword.merge(&1, global_options[:switches]))

        {opts, _} = Igniter.Util.Info.validate!(argv, info, task_name)

        Igniter.new()
        |> Map.put(:task, task_name)
        |> Igniter.Mix.Task.configure_and_run(task, argv)
        |> write(opts)
      end
    end

    defp write(igniter, opts) do
      opts = Keyword.put(opts, :yes, igniter.args.options[:yes])
      igniter = if opts[:yes] && !opts[:dry_run], do: list_written_files(igniter), else: igniter
      Igniter.do_or_dry_run(igniter, opts)
    end

    @doc """
    Adds a notice listing the files the task creates and changes.

    With `--yes`, Igniter writes without showing its diff and lists only the
    files it removes. The notice is shown once the files are written.
    """
    def list_written_files(igniter) do
      case igniter.rewrite |> Rewrite.sources() |> Enum.flat_map(&written/1) |> Enum.sort() do
        [] ->
          igniter

        written ->
          Igniter.add_notice(igniter, """
          Files written:
          #{Enum.map_join(written, "\n", fn {change, path} -> "  #{change}: #{path}" end)}

          Review the changes in version control before committing.
          """)
      end
    end

    defp written(source) do
      path = Rewrite.Source.get(source, :path)

      cond do
        Rewrite.Source.from?(source, :string) -> [{:created, path}]
        changed?(source) -> [{:updated, path}]
        true -> []
      end
    end

    defp changed?(source) do
      Rewrite.Source.updated?(source) and
        source |> Rewrite.Source.diff(color: false) |> IO.iodata_to_binary() |> String.trim() != ""
    end

    # Mix loads the configuration before running a task. Load the dependency
    # code paths and applications (for `Application.spec/2` and `app_dir/2`),
    # but not the application's own, possibly stale, build.
    defp load_dependencies do
      MixTask.run("deps.loadpaths")
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
