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

      {patches, left} = patches(content, renamed)
      updated = Sourceror.patch_string(content, patches)

      # The last guard: a rewrite that leaves invalid code is not made
      cond do
        patches == [] ->
          warn_left(igniter, path, left)

        match?({:error, _}, Code.string_to_quoted(updated)) ->
          warn_left(igniter, path, [{:unparsable, nil, nil}])

        true ->
          igniter |> Igniter.update_file(path, &Source.update(&1, :content, fn _ -> updated end)) |> warn_left(path, left)
      end
    end

    # `{patches, left}`: a patch per renamed module name in the file, and
    # what the task leaves for the developer
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
    # ones. A nested module is a scope of its own that inherits them.
    defp patch_scope(body, outer, acc) do
      ctx = scope_context(body, outer)

      {_ast, acc} =
        Macro.prewalk(body, acc, fn
          {:defmodule, _, [_name, block]}, acc -> {:ok, patch_scope(block, ctx, acc)}
          node, acc -> patch(node, ctx, acc)
        end)

      acc
    end

    # `short => entry` for the aliases visible in `body`. The entry of a
    # renamed module says what happens to its declaration and its uses, from
    # how it is used everywhere it reaches, nested modules included:
    #
    #   * :keep — used only for modules under the old name (`Meta.HTML`),
    #     which did not move: the alias stays as it is.
    #   * :follow — a plain alias whose short name changes (`Upload` →
    #     `Store`): its uses follow.
    #   * :rename — the short name stays (`as:`, or the same last segment).
    #   * :rename_as — the new short name is another alias's: `as:` keeps
    #     the old one.
    #   * :left — in braces the new name cannot share: reported.
    #
    # Under :follow, :rename and :rename_as a module under the old name is
    # spelled out in full (`Brando.Meta.HTML`).
    #
    # Only aliases at the top of the body count: one inside a function or
    # another block reaches less than the module, so it is left and reported.
    defp scope_context(body, outer) do
      direct = body |> statements() |> Enum.filter(&match?({:alias, _, _}, &1))

      taken =
        Map.keys(outer.aliases) ++ Enum.map(alias_declarations(body), & &1.short) ++ nested_module_names(body)

      aliases =
        direct
        |> alias_declarations()
        |> Enum.reduce(outer.aliases, fn declaration, aliases ->
          Map.put(aliases, declaration.short, alias_entry(declaration, body, outer.renamed, taken))
        end)

      %{renamed: outer.renamed, aliases: aliases, direct: MapSet.new(direct, &node_position/1)}
    end

    defp statements([{{:__block__, _, [:do]}, body}]), do: statements(body)
    defp statements({:__block__, _, statements}) when is_list(statements), do: statements
    defp statements(statement), do: [statement]

    defp node_position({_, meta, _}), do: {meta[:line], meta[:column]}

    # A nested `defmodule Store` aliases `Store` where it is defined
    defp nested_module_names(body) do
      {_ast, names} =
        Macro.prewalk(body, [], fn
          {:defmodule, _, [{:__aliases__, _, [name | _]} | _]} = node, names when is_atom(name) -> {node, [name | names]}
          node, names -> {node, names}
        end)

      names
    end

    defp alias_entry(%{module: module} = declaration, body, renamed, taken) do
      new = renamed[module]
      mode = if new, do: alias_mode(declaration, new, alias_uses(body, declaration.short), taken)
      Map.merge(declaration, %{new: new, mode: mode})
    end

    defp alias_mode(declaration, new, uses, taken) do
      new_short = short_name(new)

      cond do
        uses == MapSet.new([:nested]) -> :keep
        declaration.base && !relative_parts(declaration.base, new) -> :left
        declaration.as || new_short == declaration.short -> :rename
        new_short in taken -> taken_mode(declaration)
        true -> :follow
      end
    end

    # A brace alias cannot take `as:`
    defp taken_mode(%{base: nil}), do: :rename_as
    defp taken_mode(_braced), do: :left

    defp without_nested_modules(body) do
      Macro.prewalk(body, fn
        {:defmodule, _, _} -> :ok
        node -> node
      end)
    end

    # Every alias in `ast`: `%{module, short, as, base}`; `base` is the
    # brace alias's prefix, nil for a plain alias
    defp alias_declarations(ast) do
      {_ast, declarations} =
        Macro.prewalk(ast, [], fn
          {:alias, _, [{:__aliases__, _, parts} | options]} = node, acc ->
            {node, declaration(alias_module(parts), alias_as(options), nil, acc)}

          {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
            {node, Enum.reduce(children, acc, &braced_declaration(&1, base, &2))}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(declarations)
    end

    defp braced_declaration({:__aliases__, _, parts}, base, acc),
      do: declaration(alias_module(base ++ parts), nil, base, acc)

    defp braced_declaration(_child, _base, acc), do: acc

    defp declaration(nil, _as, _base, acc), do: acc

    defp declaration(module, as, base, acc),
      do: [%{module: module, as: as, short: as || short_name(module), base: base} | acc]

    defp alias_as([options]) when is_list(options) do
      Enum.find_value(options, fn
        {{:__block__, _, [:as]}, {:__aliases__, _, [as]}} -> as
        _ -> nil
      end)
    end

    defp alias_as(_options), do: nil

    # How a short name is used where its alias reaches: `:bare` on its own
    # (`Meta`, `%Meta{}`, `Meta.changeset(…)`), `:nested` with more segments
    # (`Meta.HTML`). A nested module that aliases the short name itself is
    # out of reach.
    defp alias_uses(body, short) do
      {_ast, uses} =
        Macro.prewalk(body, MapSet.new(), fn
          # `alias Meta.HTML` reaches a module under the old name
          {:alias, _, [{:__aliases__, _, [^short, _ | _]} | _]}, uses ->
            {:ok, MapSet.put(uses, :nested)}

          {:alias, _, _}, uses ->
            {:ok, uses}

          {:defmodule, _, [_name, block]} = node, uses ->
            if Enum.any?(block |> without_nested_modules() |> alias_declarations(), &(&1.short == short)),
              do: {:ok, uses},
              else: {node, uses}

          {:__aliases__, _, [^short]} = node, uses ->
            {node, MapSet.put(uses, :bare)}

          {:__aliases__, _, [^short | _]} = node, uses ->
            {node, MapSet.put(uses, :nested)}

          node, uses ->
            {node, uses}
        end)

      uses
    end

    ## Patches

    defp patch({:alias, _, _} = node, ctx, acc) do
      if MapSet.member?(ctx.direct, node_position(node)),
        do: {:ok, patch_alias(node, ctx, acc)},
        else: {:ok, leave_alias(node, ctx, acc)}
    end

    defp patch({:match, [{:scope_alias, scope} | _] = meta, [verb, path, {:__aliases__, _, parts} | rest]}, ctx, acc) do
      {{:match, meta, [verb, path | rest]}, leave_match_route(scope, parts, meta, ctx, acc)}
    end

    defp patch({verb, [{:scope_alias, scope} | _] = meta, [path, {:__aliases__, _, parts} = plug | rest]}, ctx, acc) do
      acc =
        case ctx.renamed[Module.concat(scope ++ parts)] do
          nil -> acc
          new -> patch_scoped_route(verb, meta, {plug, parts}, rest, {scope, new}, acc)
        end

      {{verb, meta, [path | rest]}, acc}
    end

    defp patch({:__aliases__, _, [first | rest] = parts} = node, ctx, {patches, left} = acc) do
      cond do
        new = ctx.renamed[alias_module(parts)] ->
          {node, {[module_patch(node, inspect(new)) | patches], left}}

        change = Enum.all?(rest, &is_atom/1) && alias_use_change(ctx.aliases[first], rest) ->
          {node, {[module_patch(node, change) | patches], left}}

        true ->
          {node, acc}
      end
    end

    defp patch(node, _ctx, acc), do: {node, acc}

    # A relative alias (`alias Meta.HTML` after `alias Brando.Meta`) follows
    # what its first segment does
    defp patch_alias({:alias, _, [{:__aliases__, _, [first | [_ | _] = rest]} = target | _]}, ctx, {patches, left} = acc)
         when is_atom(first) and is_map_key(ctx.aliases, first) do
      case Enum.all?(rest, &is_atom/1) && alias_use_change(ctx.aliases[first], rest) do
        change when is_binary(change) -> {[module_patch(target, change) | patches], left}
        _ -> acc
      end
    end

    defp patch_alias({:alias, _, [{:__aliases__, _, parts} = target | options]}, ctx, {patches, left} = acc) do
      case alias_module(parts) && ctx.aliases[alias_as(options) || short_name(alias_module(parts))] do
        %{new: new, mode: mode} when mode in [:follow, :rename] ->
          {[module_patch(target, inspect(new)) | patches], left}

        %{new: new, mode: :rename_as, short: short} ->
          {[module_patch(target, "#{inspect(new)}, as: #{short}") | patches], left}

        _ ->
          acc
      end
    end

    # A brace alias, child by child
    defp patch_alias({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]}, ctx, acc) do
      Enum.reduce(children, acc, &patch_braced(&1, base, ctx, &2))
    end

    defp patch_alias(_node, _ctx, acc), do: acc

    # An alias inside a function or block: reported when it names a renamed
    # module, and left as it is
    defp leave_alias({:alias, meta, _} = node, ctx, {patches, left} = acc) do
      case node |> List.wrap() |> alias_declarations() |> Enum.find(&Map.has_key?(ctx.renamed, &1.module)) do
        nil -> acc
        %{module: module} -> {patches, [{:alias_in_block, module, meta[:line]} | left]}
      end
    end

    defp alias_use_change(%{mode: :follow, new: new}, []), do: Atom.to_string(short_name(new))

    defp alias_use_change(%{mode: mode, module: module}, [_ | _] = rest) when mode in [:follow, :rename, :rename_as],
      do: inspect(Module.concat([module | rest]))

    defp alias_use_change(_entry, _rest), do: nil

    defp patch_braced({:__aliases__, _, parts} = child, base, ctx, {patches, left} = acc) do
      module = alias_module(base ++ parts)

      case module && ctx.aliases[short_name(module)] do
        %{module: ^module, mode: mode, new: new} when mode in [:follow, :rename] ->
          {[module_patch(child, Enum.join(relative_parts(base, new), ".")) | patches], left}

        %{module: ^module, mode: :left} ->
          {patches, [{:braced, module} | left]}

        _ ->
          acc
      end
    end

    defp patch_braced(_child, _base, _ctx, acc), do: acc

    @http_verbs [:get, :post, :put, :patch, :delete, :options, :head]

    # Relative to the scope when the new name is under its alias. Otherwise
    # the full name and `alias: false`, inserted after the last argument so
    # the route keeps its layout and comments; only for an HTTP verb whose
    # options, if any, are a plain keyword list without `alias:`.
    defp patch_scoped_route(verb, meta, {plug, parts}, rest, {scope, new}, {patches, left} = acc) do
      cond do
        verb not in @http_verbs ->
          leave_scoped_route(scope, parts, meta, new, acc)

        new_parts = relative_parts(scope, new) ->
          {[module_patch(plug, Enum.join(new_parts, ".")) | patches], left}

        insert_at = alias_false_position(rest) ->
          insert = Sourceror.Patch.new(%Sourceror.Range{start: insert_at, end: insert_at}, ", alias: false", false)
          {[insert, module_patch(plug, inspect(new)) | patches], left}

        true ->
          leave_scoped_route(scope, parts, meta, new, acc)
      end
    end

    # `match` and the other forms the task does not rewrite: reported
    defp leave_match_route(scope, parts, meta, ctx, acc) do
      case ctx.renamed[Module.concat(scope ++ parts)] do
        nil -> acc
        new -> leave_scoped_route(scope, parts, meta, new, acc)
      end
    end

    defp leave_scoped_route(scope, parts, meta, new, {patches, left}),
      do: {patches, [{:route, Module.concat(scope ++ parts), new, meta[:line]} | left]}

    # Where `, alias: false` can go: after the action, or after the last
    # option's value. Only after a node whose range is all of its text (a
    # plain literal, a map, a module name): a parenthesised or computed one
    # (`(:show)`, `if …`) is left to the developer.
    defp alias_false_position([action]), do: if(plain_node?(action), do: Sourceror.get_range(action).end)

    defp alias_false_position([_action, [_ | _] = options]) do
      keys = Enum.map(options, fn {key, _value} -> key end)
      [{_key, value} | _] = Enum.reverse(options)

      if Enum.all?(keys, &match?({:__block__, _, [key]} when is_atom(key) and key not in [:alias, :do], &1)) and
           plain_node?(value) do
        Sourceror.get_range(value).end
      end
    end

    defp alias_false_position(_rest), do: nil

    defp plain_node?({_, meta, _} = node) do
      not Keyword.has_key?(meta, :parens) and plain_literal?(node)
    end

    defp plain_node?(_node), do: false

    defp plain_literal?({:__block__, meta, [value]}) when is_binary(value), do: meta[:delimiter] == ~s(")
    defp plain_literal?({:__block__, _, [value]}), do: is_atom(value) or is_number(value)
    defp plain_literal?({:%{}, _, _}), do: true
    defp plain_literal?({:__aliases__, _, _}), do: true
    defp plain_literal?(_node), do: false

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

    defp warn_left(igniter, path, left) do
      Enum.reduce(left, igniter, fn
        {:braced, module}, igniter ->
          Igniter.add_warning(igniter, """
          #{path} aliases #{inspect(module)} inside braces, where its new name \
          (#{inspect(RenamedModules.new_name(module))}) cannot go. Alias the new name on its own \
          line; the old name keeps working, with a warning, until 0.57.
          """)

        {:alias_in_block, module, line}, igniter ->
          Igniter.add_warning(igniter, """
          #{path}:#{line} aliases #{inspect(module)} inside a function or block, which this task \
          does not rewrite. Use #{inspect(RenamedModules.new_name(module))} there; the old name keeps \
          working, with a warning, until 0.57.
          """)

        {:unparsable, _, _}, igniter ->
          Igniter.add_warning(igniter, """
          #{path} names modules renamed in 0.55, but rewriting them did not leave valid Elixir, so the \
          file is unchanged. `mix brando.doctor` lists the old names to replace.
          """)

        {:route, module, new, line}, igniter ->
          Igniter.add_warning(igniter, """
          #{path}:#{line} routes to #{inspect(module)} through its scope's alias, in a form this task \
          does not rewrite. Name the controller #{inspect(new)} and add `alias: false` to the route; \
          the old name keeps working, with a warning, until 0.57.
          """)
      end)
    end
  end
else
  defmodule Mix.Brando.Igniter.ModuleRenames do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
