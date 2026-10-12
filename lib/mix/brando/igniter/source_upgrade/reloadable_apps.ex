if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.ReloadableApps do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # An endpoint's `reloadable_apps` that lists a dependency (`:brando`)
    # has the code reloader check that dependency's sources on every dev
    # request, and since Elixir 1.19 compiling a dependency deletes the
    # application's consolidated protocols, which the next request then
    # rebuilds. Brando's installer never set it. Phoenix's default, `nil`, is
    # the application itself, so a literal list that names a dependency loses
    # the key; what remains of it is at most the application. Umbrella
    # projects, whose default is every child application, are left alone.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Application, as: ProjectApplication
    alias Rewrite.Source
    alias Sourceror.Zipper

    @doc "Drops `reloadable_apps:` that name a dependency from `config/*.exs`, and lists each one."
    def drop_dependencies(igniter) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")
      app = ProjectApplication.app_name(igniter)

      if umbrella?(igniter) do
        igniter
      else
        {igniter, dropped} =
          igniter.rewrite
          |> Rewrite.sources()
          |> Enum.filter(&(Path.dirname(&1.path) == "config" and Source.get(&1, :content) =~ "reloadable_apps"))
          |> Enum.map(&Source.get(&1, :path))
          |> Enum.sort()
          |> Enum.reduce({igniter, []}, &drop_in(&1, &2, app))

        notice(igniter, dropped)
      end
    end

    defp umbrella?(igniter) do
      Igniter.exists?(igniter, "mix.exs") and
        igniter
        |> Igniter.include_existing_file("mix.exs")
        |> Map.fetch!(:rewrite)
        |> Rewrite.source!("mix.exs")
        |> Source.get(:content) =~
          ~r/\bapps_path:/
    end

    defp drop_in(path, {igniter, dropped}, app) do
      zipper = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:quoted) |> Zipper.zip()

      found =
        for config <- Common.find_all(zipper, &CodeFunction.function_call?(&1, :config, 3)),
            {line, apps} <- [reloadable_apps(config)],
            Enum.any?(apps, &(&1 != app)),
            do: {path, line, apps}

      if found == [] do
        {igniter, dropped}
      else
        lines = Enum.map(found, &elem(&1, 1))

        igniter =
          Igniter.update_elixir_file(igniter, path, fn zipper ->
            Common.update_all_matches(zipper, &dropped_config?(&1, lines, app), &drop_key/1)
          end)

        {igniter, dropped ++ found}
      end
    end

    defp dropped_config?(zipper, lines, app) do
      with true <- CodeFunction.function_call?(zipper, :config, 3),
           {line, apps} <- reloadable_apps(zipper) do
        line in lines and Enum.any?(apps, &(&1 != app))
      else
        _ -> false
      end
    end

    # `{line, apps}` for a literal list of atoms, or nil.
    defp reloadable_apps(config) do
      with {:ok, options} <- CodeFunction.move_to_nth_argument(config, 2),
           true <- Igniter.Code.List.list?(options),
           {:ok, value} <- Igniter.Code.Keyword.get_key(options, :reloadable_apps),
           # `get_key/2` unwraps the list's block.
           [{_, meta, _} | _] = elements <- Zipper.node(value),
           apps = Enum.map(elements, &unwrap/1),
           true <- Enum.all?(apps, &is_atom/1) do
        {meta[:line], apps}
      else
        _ -> nil
      end
    end

    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value

    defp drop_key(zipper) do
      with {:ok, options} <- CodeFunction.move_to_nth_argument(zipper, 2),
           {:ok, options} <- Igniter.Code.Keyword.remove_keyword_key(options, :reloadable_apps) do
        {:ok, Zipper.up(options)}
      else
        _ -> {:ok, zipper}
      end
    end

    defp notice(igniter, []), do: igniter

    defp notice(igniter, dropped) do
      Igniter.add_notice(igniter, """
      Removed `reloadable_apps` from the endpoint config: it named a
      dependency, so the code reloader checked that dependency's sources on
      every development request (since Elixir 1.19 it also rebuilt the
      application's protocols each time). Phoenix's default reloads the
      application itself:

      #{Enum.map_join(dropped, "\n", fn {path, line, apps} -> "  #{path}:#{line}: reloadable_apps: #{inspect(apps)}" end)}
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.ReloadableApps do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
