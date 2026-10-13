if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.ReloadableApps do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # An endpoint's `reloadable_apps` that lists a dependency (`:brando`)
    # has the code reloader check that dependency's sources on every dev
    # request, and since Elixir 1.19 compiling a dependency deletes the
    # application's consolidated protocols, which the next request then
    # rebuilds. Brando's installer never set it. `:brando` and the Hex and git
    # dependencies `mix.exs` declares leave a literal list; the application
    # and path dependencies, which a team may edit alongside it, stay. A list
    # left with at most the application loses the key: Phoenix's default,
    # `nil`, is the application itself. Umbrella projects, whose default is
    # every child application, are left alone.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Application, as: ProjectApplication
    alias Rewrite.Source
    alias Sourceror.Zipper

    @doc "Drops `:brando` and Hex and git dependencies from `reloadable_apps:` in `config/*.exs`, and lists each list."
    def drop_dependencies(igniter) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")
      app = ProjectApplication.app_name(igniter)
      {igniter, mix_exs} = mix_exs(igniter)

      if mix_exs =~ ~r/\bapps_path:/ do
        igniter
      else
        dropped? = &(&1 == :brando or &1 in fetched_dependencies(mix_exs))

        {igniter, changed} =
          igniter.rewrite
          |> Rewrite.sources()
          |> Enum.filter(&(Path.dirname(&1.path) == "config" and Source.get(&1, :content) =~ "reloadable_apps"))
          |> Enum.map(&Source.get(&1, :path))
          |> Enum.sort()
          |> Enum.reduce({igniter, []}, &drop_in(&1, &2, app, dropped?))

        notice(igniter, changed)
      end
    end

    defp mix_exs(igniter) do
      if Igniter.exists?(igniter, "mix.exs") do
        igniter = Igniter.include_existing_file(igniter, "mix.exs")
        {igniter, igniter.rewrite |> Rewrite.source!("mix.exs") |> Source.get(:content)}
      else
        {igniter, ""}
      end
    end

    # The dependencies `mix.exs` declares without `path:` (or `in_umbrella:`).
    defp fetched_dependencies(mix_exs) do
      case Sourceror.parse_string(mix_exs) do
        {:ok, ast} ->
          {_ast, deps} =
            Macro.prewalk(ast, [], fn
              {:{}, _, [name | rest]} = node, deps -> {node, dependency(name, rest, deps)}
              {:__block__, _, [{name, second}]} = node, deps -> {node, dependency(name, [second], deps)}
              node, deps -> {node, deps}
            end)

          deps

        _error ->
          []
      end
    end

    defp dependency(name, rest, deps) do
      with name when is_atom(name) and not is_nil(name) <- unwrap(name),
           false <- Enum.any?(rest, &local_option?/1) do
        [name | deps]
      else
        _ -> deps
      end
    end

    defp local_option?(options) when is_list(options),
      do:
        Enum.any?(
          options,
          &(match?({key, _value} when is_tuple(key), &1) and unwrap(elem(&1, 0)) in [:path, :in_umbrella])
        )

    defp local_option?({:__block__, _, [options]}) when is_list(options), do: local_option?(options)
    defp local_option?(_option), do: false

    defp drop_in(path, {igniter, changed}, app, dropped?) do
      zipper = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:quoted) |> Zipper.zip()

      found =
        for config <- Common.find_all(zipper, &CodeFunction.function_call?(&1, :config, 3)),
            {line, apps} <- [reloadable_apps(config)],
            Enum.any?(apps, dropped?),
            kept = Enum.reject(apps, dropped?),
            do: {path, line, apps, if(kept in [[], [app]], do: :removed, else: kept)}

      if found == [] do
        {igniter, changed}
      else
        igniter =
          Igniter.update_elixir_file(igniter, path, fn zipper ->
            Common.update_all_matches(zipper, &changed_config?(&1, found), &update_key(&1, found))
          end)

        {igniter, changed ++ found}
      end
    end

    defp changed_config?(zipper, found) do
      with true <- CodeFunction.function_call?(zipper, :config, 3),
           {line, _apps} <- reloadable_apps(zipper) do
        Enum.any?(found, &(elem(&1, 1) == line))
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

    defp update_key(zipper, found) do
      {line, _apps} = reloadable_apps(zipper)
      {_path, _line, _apps, kept} = Enum.find(found, &(elem(&1, 1) == line))

      with {:ok, options} <- CodeFunction.move_to_nth_argument(zipper, 2),
           {:ok, options} <- kept_key(options, kept) do
        {:ok, Zipper.up(options)}
      else
        _ -> {:ok, zipper}
      end
    end

    defp kept_key(options, :removed), do: Igniter.Code.Keyword.remove_keyword_key(options, :reloadable_apps)

    defp kept_key(options, kept) do
      Igniter.Code.Keyword.set_keyword_key(options, :reloadable_apps, kept, fn zipper ->
        {:ok, Common.replace_code(zipper, kept)}
      end)
    end

    defp notice(igniter, []), do: igniter

    defp notice(igniter, changed) do
      Igniter.add_notice(igniter, """
      Removed Brando and the Hex and git dependencies from the endpoint's
      `reloadable_apps`: the code reloader checked their sources on every
      development request (since Elixir 1.19 it also rebuilt the
      application's protocols each time). The application and path
      dependencies, which you may edit alongside it, stay; a list left with
      only the application goes, since Phoenix's default reloads it:

      #{Enum.map_join(changed, "\n", &changed_line/1)}
      """)
    end

    defp changed_line({path, line, apps, :removed}), do: "  #{path}:#{line}: reloadable_apps: #{inspect(apps)}, removed"

    defp changed_line({path, line, apps, kept}),
      do: "  #{path}:#{line}: reloadable_apps: #{inspect(apps)}, now #{inspect(kept)}"
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.ReloadableApps do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
