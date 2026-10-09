if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.ModuleRenames do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Rewrites references to the public modules renamed in 0.55
    # (`Brando.Deprecated.RenamedModules`) for `mix brando.migrate55`.

    alias Brando.Deprecated.RenamedModules
    alias Rewrite.Source

    @doc """
    Points references to the public modules renamed in 0.55 at their new
    names: routers, sockets, endpoint config and code under `config/`, `lib/`
    and `test/`.

    The source is read as code and only the module names are replaced, so
    `Brando.Meta.HTML` is not `Brando.Meta`, and the rest of a file keeps its
    formatting. Aliases are resolved per module, as Elixir does:

      * Behind a plain `alias`, a short name follows its module when the last
        segment changes (`Upload` becomes `Store`). Where the new short name
        is another alias's, the alias keeps the old one with `as:`.
      * A module under the old name did not move: `Meta.HTML` after
        `alias Brando.Meta` is spelled out in full, and an alias used only for
        such modules is left as it is.
      * A route inside `scope "/", Brando do` names its controller relative to
        the scope. It gets the new name with `alias: false`, or a relative
        name when the new one is under the scope's alias.
      * An alias inside braces that the new name cannot share
        (`alias Brando.{LobbyChannel}`, now `BrandoAdmin`) is left for the
        developer and reported. The old name keeps working until 0.57.
    """
    def rewrite(igniter) do
      renamed = RenamedModules.all()
      igniter = Igniter.include_glob(igniter, "{config,lib,test}/**/*.{ex,exs}")

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.filter(&(String.starts_with?(&1, ["config/", "lib/", "test/"]) and Path.extname(&1) in [".ex", ".exs"]))
      |> Enum.sort()
      |> Enum.reduce(igniter, &rewrite_file(&2, &1, renamed))
    end

    defp rewrite_file(igniter, path, renamed) do
      content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

      case patches(content, renamed) do
        {[], []} ->
          igniter

        {patches, left} ->
          igniter
          |> Igniter.update_file(
            path,
            &Source.update(&1, :content, fn content -> Sourceror.patch_string(content, patches) end)
          )
          |> warn_braced(path, left)
      end
    end

    # `{patches, left}`: a patch per renamed module name in the file, and
    # the braced aliases the new names cannot share
    defp patches(content, renamed) do
      case Sourceror.parse_string(content) do
        {:ok, ast} ->
          ast = RenamedModules.mark_scoped_routes(ast)
          {patches, left} = patch_scope(ast, %{renamed: renamed, aliases: %{}}, {[], []})
          {patches, Enum.reverse(left)}

        {:error, _} ->
          {[], []}
      end
    end

    ## Lexical scopes

    # The file, or a module's body: its own aliases on top of the enclosing
    # ones. Nested modules are scopes of their own.
    defp patch_scope(body, outer, acc) do
      ctx = scope_context(body, outer)

      {_ast, acc} =
        Macro.prewalk(body, acc, fn
          {:defmodule, _, [_name, block]}, acc -> {:ok, patch_scope(block, ctx, acc)}
          node, acc -> patch(node, ctx, acc)
        end)

      acc
    end

    defp scope_context(body, outer) do
      own = without_nested_modules(body)

      aliases =
        own
        |> alias_declarations()
        |> Enum.reduce(outer.aliases, fn {module, as}, aliases -> Map.put(aliases, as || short_name(module), module) end)

      # Plain aliases of renamed modules: those whose short name is their own
      plain = for {short, module} <- aliases, Map.has_key?(outer.renamed, module), short == short_name(module), do: module
      uses = short_name_uses(own, Enum.map(plain, &short_name/1))

      # Used only for modules under the old name (`Meta.HTML`): left alone
      kept = Enum.filter(plain, &(uses[short_name(&1)] == :nested))
      followed = plain -- kept

      keep_as =
        Enum.filter(followed, fn module ->
          new_short = short_name(outer.renamed[module])
          new_short != short_name(module) and Map.has_key?(aliases, new_short)
        end)

      %{
        renamed: outer.renamed,
        aliases: aliases,
        short: Map.new(followed, &{short_name(&1), &1}),
        kept: kept,
        keep_as: keep_as
      }
    end

    defp without_nested_modules(body) do
      Macro.prewalk(body, fn
        {:defmodule, _, _} -> :ok
        node -> node
      end)
    end

    # `{module, as}` for every alias in `ast`; `as` is nil without `as:`
    defp alias_declarations(ast) do
      {_ast, declarations} =
        Macro.prewalk(ast, [], fn
          {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
            {node, [{alias_module(parts), nil} | acc]}

          {:alias, _, [{:__aliases__, _, parts}, opts]} = node, acc ->
            {node, [{alias_module(parts), alias_as(opts)} | acc]}

          {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
            {node, for({:__aliases__, _, parts} <- children, do: {alias_module(base ++ parts), nil}) ++ acc}

          node, acc ->
            {node, acc}
        end)

      declarations |> Enum.reject(&match?({nil, _}, &1)) |> Enum.reverse()
    end

    defp alias_as(opts) do
      Enum.find_value(List.wrap(opts), fn
        {{:__block__, _, [:as]}, {:__aliases__, _, [as]}} -> as
        {:as, {:__aliases__, _, [as]}} -> as
        _ -> nil
      end)
    end

    # `short => :bare` when a short name is used on its own anywhere
    # (`Meta`, `%Meta{}`), `:nested` when only with more segments (`Meta.HTML`)
    defp short_name_uses(ast, shorts) do
      {_ast, uses} =
        Macro.prewalk(ast, %{}, fn
          {:alias, _, _}, uses ->
            {:ok, uses}

          {:__aliases__, _, [first | rest]} = node, uses ->
            cond do
              first not in shorts -> {node, uses}
              rest == [] -> {node, Map.put(uses, first, :bare)}
              true -> {node, Map.update(uses, first, :nested, & &1)}
            end

          node, uses ->
            {node, uses}
        end)

      uses
    end

    ## Patches

    defp patch({:alias, _, [{:__aliases__, _, parts} = target]} = node, ctx, {patches, left} = acc) do
      module = alias_module(parts)

      cond do
        module in ctx.kept ->
          {:ok, acc}

        module in ctx.keep_as ->
          change = "#{inspect(ctx.renamed[module])}, as: #{short_name(module)}"
          {:ok, {[module_patch(target, change) | patches], left}}

        true ->
          {node, acc}
      end
    end

    # The braced alias is handled here, child by child, and not walked again
    defp patch({{:., _, [{:__aliases__, _, base}, :{}]}, _, children}, ctx, acc) when is_list(children) do
      {:ok, Enum.reduce(children, acc, &patch_braced(&1, base, ctx, &2))}
    end

    defp patch({verb, [{:scope_alias, scope} | _] = meta, [path, {:__aliases__, _, parts} | rest]} = node, ctx, acc) do
      new = ctx.renamed[Module.concat(scope ++ parts)]
      acc = if new, do: patch_scoped_route(node, scope, new, acc), else: acc
      {{verb, meta, [path | rest]}, acc}
    end

    defp patch({:__aliases__, _, [first | rest] = parts} = node, ctx, {patches, left} = acc) do
      cond do
        new = ctx.renamed[alias_module(parts)] ->
          {node, {[module_patch(node, inspect(new)) | patches], left}}

        Map.has_key?(ctx.short, first) and Enum.all?(rest, &is_atom/1) ->
          case short_name_change(ctx.short[first], rest, ctx) do
            nil -> {node, acc}
            change -> {node, {[module_patch(node, change) | patches], left}}
          end

        true ->
          {node, acc}
      end
    end

    defp patch(node, _ctx, acc), do: {node, acc}

    # Through the alias. `Upload` follows `alias Brando.Upload` to
    # `Brando.Uploads.Store` as `Store`. A module under the old name did not
    # move, so `Meta.HTML` is spelled out where the alias now names the new one.
    defp short_name_change(old, [], ctx) do
      new_short = short_name(ctx.renamed[old])
      if new_short != short_name(old) and old not in ctx.keep_as, do: Atom.to_string(new_short)
    end

    defp short_name_change(old, rest, _ctx), do: inspect(Module.concat([old | rest]))

    defp patch_braced({:__aliases__, _, parts} = child, base, ctx, {patches, left} = acc) do
      module = alias_module(base ++ parts)
      new = ctx.renamed[module]

      cond do
        is_nil(new) or module in ctx.kept -> acc
        module in ctx.keep_as -> {patches, [module | left]}
        new_parts = relative_parts(base, new) -> {[module_patch(child, Enum.join(new_parts, ".")) | patches], left}
        true -> {patches, [module | left]}
      end
    end

    defp patch_braced(_child, _base, _ctx, acc), do: acc

    # Relative to the scope when the new name is under its alias; else the
    # full name, and `alias: false` so Phoenix does not prefix it
    defp patch_scoped_route({verb, _, [path, plug | rest]} = call, scope, new, {patches, left} = acc) do
      cond do
        new_parts = relative_parts(scope, new) ->
          {[module_patch(plug, Enum.join(new_parts, ".")) | patches], left}

        Enum.any?(rest, &do_block?/1) ->
          acc

        true ->
          args = [Sourceror.to_string(path), inspect(new) | route_options(rest)]
          {[module_patch(call, "#{verb} #{Enum.join(args, ", ")}") | patches], left}
      end
    end

    # A route's arguments after the plug, with `alias: false` added to its
    # options (the last argument, when it has them)
    defp route_options([action]), do: [Sourceror.to_string(action), "alias: false"]

    defp route_options([action, options]) when is_list(options) do
      alias_false = {{:__block__, [format: :keyword], [:alias]}, {:__block__, [], [false]}}
      keywords = Sourceror.to_string(options ++ [alias_false])
      [Sourceror.to_string(action), String.slice(keywords, 1..-2//1)]
    end

    defp route_options(rest), do: Enum.map(rest, &Sourceror.to_string/1) ++ ["alias: false"]

    defp do_block?(arg) do
      is_list(arg) and Enum.any?(arg, &match?({{:__block__, _, [:do]}, _}, &1))
    end

    defp module_patch(node, change), do: Sourceror.Patch.new(Sourceror.get_range(node), change, false)

    defp alias_module(parts) do
      if Enum.all?(parts, &is_atom/1), do: Module.concat(parts)
    end

    defp short_name(module), do: module |> Module.split() |> List.last() |> String.to_atom()

    # The new name's segments after `base`, or nil when it does not start
    # with them
    defp relative_parts(base, new) do
      new_parts = new |> Module.split() |> Enum.map(&String.to_atom/1)
      if List.starts_with?(new_parts, base), do: Enum.drop(new_parts, length(base))
    end

    defp warn_braced(igniter, _path, []), do: igniter

    defp warn_braced(igniter, path, modules) do
      Igniter.add_warning(igniter, """
      #{path} aliases #{Enum.map_join(modules, ", ", &inspect/1)} inside braces, where the \
      new #{if length(modules) == 1, do: "name", else: "names"} \
      (#{Enum.map_join(modules, ", ", &inspect(RenamedModules.new_name(&1)))}) cannot go. Alias \
      the new name on its own line; the old name keeps working, with a warning, until 0.57.
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.ModuleRenames do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
