if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.Datasources do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.53's `use Brando.Datasource` kept list, single and selection
    # datasources apart, so `list :all` and `selection :all` could share a
    # name. 0.54's `datasource :all do type … end` cannot: the Blueprint
    # refuses to compile with `datasource :all is declared more than once`.
    # Before the rewrite, the single or selection datasource that shares a
    # list's name (or a selection one that shares a single's) gets
    # `<name>_<type>`, and the renames are listed: content modules store the
    # name they select from.
    #
    # `use Brando.Datasource` also did `import Ecto.Query`. A module whose
    # functions call its macros gets an `import Ecto.Query, only: […]` in
    # the `use`'s place.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Rewrite.Source
    alias Sourceror.Zipper

    @legacy [list: 2, single: 2, selection: 3]
    # Renamed first to last: a list keeps its name, then a single.
    @order %{list: 0, single: 1, selection: 2}

    @query_macros ~w(distinct dynamic exclude first from group_by having join last limit offset
                     or_having or_where order_by preload select select_merge subquery where)a

    @doc """
    Renames the single and selection datasources of the application's
    Blueprints that share a name with another legacy datasource, and lists
    each rename with file and line.
    """
    def rename_shared_names(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)
      {igniter, renames} = Enum.reduce(blueprints, {igniter, []}, &rename_module/2)
      notice(igniter, renames)
    end

    defp rename_module(module, {igniter, renames}) do
      {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)

      case plan(zipper) do
        [] ->
          {igniter, renames}

        planned ->
          path = Source.get(source, :path)
          found = for {line, type, from, to} <- planned, do: {path, line, module, type, from, to}
          {ProjectModule.find_and_update_module!(igniter, module, &rename(&1, planned)), renames ++ found}
      end
    end

    # `{line, type, old_name, new_name}` for each legacy datasource to rename.
    defp plan(zipper) do
      declared =
        zipper
        |> Common.find_all(&legacy_datasource?/1)
        |> Enum.map(fn zipper ->
          {type, meta, [key | _]} = Zipper.node(zipper)
          {type, unwrap(key), meta[:line]}
        end)

      taken = MapSet.new(declared, &elem(&1, 1))

      {renames, _taken} =
        declared
        |> Enum.group_by(&elem(&1, 1))
        |> Enum.filter(fn {_name, datasources} -> match?([_, _ | _], datasources) end)
        |> Enum.sort()
        |> Enum.flat_map(fn {_name, datasources} -> datasources |> Enum.sort_by(&@order[elem(&1, 0)]) |> tl() end)
        |> Enum.map_reduce(taken, fn {type, name, line}, taken ->
          new_name = free_name(:"#{name}_#{type}", taken, 2)
          {{line, type, name, new_name}, MapSet.put(taken, new_name)}
        end)

      renames
    end

    defp free_name(name, taken, n) do
      cond do
        not MapSet.member?(taken, name) -> name
        not MapSet.member?(taken, :"#{name}#{n}") -> :"#{name}#{n}"
        true -> free_name(name, taken, n + 1)
      end
    end

    defp rename(zipper, planned) do
      Common.update_all_matches(zipper, &legacy_datasource?/1, fn zipper ->
        {type, meta, [key | rest]} = Zipper.node(zipper)

        case Enum.find(planned, &planned?(&1, meta[:line], type, unwrap(key))) do
          nil ->
            {:ok, zipper}

          {_line, _type, _name, new_name} ->
            {:ok, Zipper.replace(zipper, {type, meta, [replace_atom(key, new_name) | rest]})}
        end
      end)
    end

    defp planned?({line, type, name, _new_name}, line, type, name), do: true
    defp planned?(_planned, _line, _type, _name), do: false

    defp replace_atom({:__block__, meta, [_atom]}, new_name), do: {:__block__, meta, [new_name]}
    defp replace_atom(_atom, new_name), do: new_name

    defp legacy_datasource?(zipper) do
      Enum.any?(@legacy, fn {name, arity} ->
        CodeFunction.function_call?(zipper, name, arity) and
          match?([key | _] when is_atom(key) or is_tuple(key), Sourceror.get_args(Zipper.node(zipper))) and
          is_atom(zipper |> Zipper.node() |> Sourceror.get_args() |> hd() |> unwrap())
      end)
    end

    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value

    defp notice(igniter, []), do: igniter

    defp notice(igniter, renames) do
      Igniter.add_notice(igniter, """
      These Blueprints declared two datasources under one name, which 0.53
      allowed and 0.54 refuses (`datasource :all is declared more than once`).
      The task renamed the single or selection one:

      #{Enum.map_join(renames, "\n", fn {path, line, module, type, from, to} -> "  #{path}:#{line}: #{inspect(module)} `#{type} #{inspect(from)}` is now #{inspect(to)}" end)}

      A content module that selects from a renamed datasource stores its old
      name: after upgrading the database, open each such module in the admin
      and choose the new name as its datasource.
      """)
    end

    @doc """
    The `import Ecto.Query, only: […]` a Blueprint needs once its
    `use Brando.Datasource` goes, or nil: the Ecto.Query macros its
    functions call, unless it imports Ecto.Query itself or defines a
    function of that name.
    """
    def ecto_query_import(zipper) do
      ast = zipper |> Zipper.topmost() |> Zipper.node()

      used =
        ast
        |> function_bodies()
        |> Enum.flat_map(&query_calls/1)
        |> Enum.uniq()
        |> Enum.reject(fn {name, _arity} -> name in defined_names(ast) end)
        |> Enum.sort()

      if used == [] or imports_ecto_query?(ast),
        do: nil,
        else: "import Ecto.Query, only: [#{Enum.map_join(used, ", ", fn {name, arity} -> "#{name}: #{arity}" end)}]"
    end

    defp function_bodies(ast) do
      {_ast, bodies} =
        Macro.prewalk(ast, [], fn
          {kind, _, [_head, body]} = node, bodies when kind in [:def, :defp] -> {node, [body | bodies]}
          {:fn, _, clauses} = node, bodies -> {node, [clauses | bodies]}
          node, bodies -> {node, bodies}
        end)

      bodies
    end

    defp query_calls(body) do
      {_body, calls} =
        Macro.prewalk(body, [], fn
          {name, _, args} = node, calls when name in @query_macros and is_list(args) ->
            {node, [{name, length(args)} | calls]}

          node, calls ->
            {node, calls}
        end)

      calls
    end

    defp defined_names(ast) do
      {_ast, names} =
        Macro.prewalk(ast, [], fn
          {kind, _, [{:when, _, [{name, _, _} | _]} | _]} = node, names when kind in [:def, :defp] ->
            {node, [name | names]}

          {kind, _, [{name, _, _} | _]} = node, names when kind in [:def, :defp] ->
            {node, [name | names]}

          node, names ->
            {node, names}
        end)

      names
    end

    defp imports_ecto_query?(ast) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:import, _, [{:__aliases__, _, [:Ecto, :Query]} | _]} = node, _found -> {node, true}
          node, found -> {node, found}
        end)

      found
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.Datasources do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
