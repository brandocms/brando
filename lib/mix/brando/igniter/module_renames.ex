if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.ModuleRenames do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Rewrites references to the public modules renamed in 0.55
    # (`Brando.Deprecated.RenamedModules`) for `mix brando.migrate55`.

    alias Brando.Deprecated.LexicalAliases
    alias Brando.Deprecated.RenamedModules
    alias Brando.Deprecated.TemplateCode
    alias Brando.Deprecated.TemplateHazards
    alias Rewrite.Source

    @doc """
    Points references to the public modules renamed in 0.55 at their new
    names: routers, sockets, endpoint config and code under `config/`, `lib/`
    and `test/`.

    The source is read as code and only the module names are replaced, so
    `Brando.Meta.HTML` is not `Brando.Meta`, and the rest of a file keeps its
    formatting. Aliases are resolved as Elixir does
    (`Brando.Deprecated.LexicalAliases`): an alias reaches the code after it
    in its own module, function or block, and each use follows the alias it
    comes from.

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

    A file is rewritten only if every module name in it still means the same
    module afterwards, the renamed ones aside; otherwise it is left as it is
    and reported.
    """
    def rewrite(igniter) do
      renamed = RenamedModules.all()
      igniter = Igniter.include_glob(igniter, "{config,lib,test}/**/*.{ex,exs}")
      # Every template in the project, for the safety nets
      extensions = TemplateHazards.extensions() -- ["exs"]
      igniter = Igniter.include_glob(igniter, "{config,lib,test,priv}/**/*.{#{Enum.join(extensions, ",")}}")
      igniter = Igniter.include_glob(igniter, "{config,lib,test,priv}/**/*.*.exs")

      corpus =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
        |> TemplateHazards.corpus(&read_template(igniter, &1))

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.filter(&(String.starts_with?(&1, ["config/", "lib/", "test/"]) and Path.extname(&1) in [".ex", ".exs"]))
      |> Enum.reject(&TemplateHazards.template_file?/1)
      |> Enum.sort()
      |> Enum.reduce(igniter, &rewrite_file(&2, &1, {renamed, corpus}))
    end

    defp rewrite_file(igniter, path, {renamed, corpus}) do
      content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

      {patches, left} = patches(content, renamed)
      {shorts, left} = Enum.split_with(left, &match?({:short, _}, &1))
      {hazards, left} = Enum.split_with(left, &match?({:hazard, _}, &1))
      names = {Enum.map(shorts, &elem(&1, 1)), hazards |> Enum.map(&elem(&1, 1)) |> Enum.uniq()}
      updated = Sourceror.patch_string(content, patches)

      cond do
        patches == [] ->
          warn_left(igniter, path, left)

        match?({:error, _}, Code.string_to_quoted(updated)) ->
          warn_left(igniter, path, [{:unparsable, nil, nil}])

        reason = held(igniter, path, {content, updated}, names, {renamed, corpus}) ->
          warn_left(igniter, path, [reason | left])

        true ->
          igniter |> Igniter.update_file(path, &Source.update(&1, :content, fn _ -> updated end)) |> warn_left(path, left)
      end
    end

    # The last guards: why a rewrite that would change what a module name
    # means, here or in a template, is not made; nil when it can be
    defp held(igniter, path, {content, updated}, {shorts, hazards}, {renamed, corpus}) do
      templates = templates(igniter, path)
      colocated = colocated_templates(igniter, path)

      cond do
        line = opaque_templates(content, templates, colocated) ->
          {:opaque_templates, line}

        mention = shorts != [] && template_mention(content, shorts, templates, readable(colocated)) ->
          {:template_mention, mention}

        hazard = hazards != [] && project_template(content, path, hazards, corpus, igniter) ->
          {:project_template, hazard}

        line = changed_reference({content, updated}, renamed, &readable(templates.(&1, &2))) ->
          {:changed_meaning, line}

        true ->
          nil
      end
    end

    # `{patches, left}`: a patch per renamed module name in the file, and
    # what the task leaves for the developer
    defp patches(content, renamed) do
      case Sourceror.parse_string(content) do
        {:ok, ast} ->
          ast = RenamedModules.mark_scoped_routes(ast)
          {patches, left} = patch_scope(ast, %{renamed: renamed, entries: %{}}, {[], []})
          {patches, Enum.reverse(left)}

        {:error, _} ->
          {[], []}
      end
    end

    ## Safety net

    # The line of the first module name that `updated` resolves differently
    # from `content`, the renames aside, or nil when they all agree
    defp changed_reference({content, updated}, renamed, templates) do
      before = references(content, renamed, templates)
      after_ = references(updated, renamed, templates)

      cond do
        before == :error or after_ == :error -> 1
        Enum.map(before, &elem(&1, 0)) == Enum.map(after_, &elem(&1, 0)) -> nil
        true -> first_difference(before, after_) || 1
      end
    end

    # Where only the number of references differs, the line of the last
    # one they share
    defp first_difference([{was, line} | before], [{now, _} | after_]),
      do: if(was == now, do: first_difference(before, after_) || line, else: line)

    defp first_difference([{_, line} | _], []), do: line
    defp first_difference(_before, _after), do: nil

    # `[{module, line}]` for every module name in `content`, in order, with
    # the renamed modules under their new names. An alias's `as:` is a new
    # name, not a reference; a route in an aliased scope is the module
    # Phoenix joins. Names in a template, a `~H` sigil or a file that
    # `embed_templates` compiles in, resolve through the aliases where it
    # is written; a template file's are counted on its `embed_templates`
    # line.
    defp references(content, renamed, templates) do
      case Sourceror.parse_string(content) do
        {:ok, ast} ->
          {_ast, refs} =
            ast |> RenamedModules.mark_scoped_routes() |> Macro.prewalk([], &reference(&1, &2, {renamed, templates}))

          Enum.reverse(refs)

        {:error, _} ->
          :error
      end
    end

    defp reference({form, meta, [target, _options]}, refs, ctx) when form in [:alias, :require],
      do: reference({form, meta, [target]}, refs, ctx)

    defp reference(
           {:embed_templates, [{:lexical_env, env} | _] = meta, [pattern | options]} = node,
           refs,
           {renamed, templates}
         ) do
      names =
        for {path, text} <- templates.(pattern, options),
            %{resolved: resolved} <- LexicalAliases.names_in_text(text, env, 1, TemplateCode.mode(path)),
            do: {template_reference(resolved, renamed), meta[:line]}

      {node, Enum.reverse(names, refs)}
    end

    defp reference({_sigil, [{:lexical_env, _} | _], [{:<<>>, _, _} | _]} = node, refs, {renamed, _templates}) do
      names =
        for %{resolved: resolved, line: line} <- LexicalAliases.template_names(node),
            do: {template_reference(resolved, renamed), line}

      {node, Enum.reverse(names, refs)}
    end

    defp reference(node, refs, {renamed, _templates}), do: reference(node, refs, renamed)

    defp reference({:match, [{:scope_alias, scope} | _] = meta, [verb, path, plug | rest]}, refs, renamed),
      do: {{:match, meta, [verb, path | rest]}, [scoped_reference(scope, plug, renamed) | refs]}

    defp reference({verb, [{:scope_alias, scope} | _] = meta, [path, plug | rest]}, refs, renamed),
      do: {{verb, meta, [path | rest]}, [scoped_reference(scope, plug, renamed) | refs]}

    defp reference({:__aliases__, meta, parts} = node, refs, renamed) do
      module =
        case meta[:resolved_alias] do
          {:either, candidates} -> {:either, Enum.map(candidates, &new_name(&1, renamed))}
          [_ | _] = resolved -> new_name(resolved, renamed)
          _ -> {:unresolved, Enum.map(parts, &segment_name/1)}
        end

      {node, [{module, meta[:line]} | refs]}
    end

    defp reference(node, refs, _renamed), do: {node, refs}

    defp scoped_reference(scope, {_, meta, _} = plug, renamed) do
      case RenamedModules.scoped_module(scope, plug) do
        nil -> {{:unresolved_route, scope, plug |> elem(2) |> Enum.map(&segment_name/1)}, meta[:line]}
        module -> {Map.get(renamed, module, module), meta[:line]}
      end
    end

    defp template_reference({:either, candidates}, renamed), do: {:either, Enum.map(candidates, &new_name(&1, renamed))}
    defp template_reference(resolved, renamed), do: new_name(resolved, renamed)

    # `[{path, text}]` for the templates `embed_templates pattern, root: …`
    # compiles into the module at `path`
    defp templates(igniter, path), do: &read_templates(igniter, path, &1, &2)

    defp read_templates(igniter, path, pattern, options) do
      case TemplateCode.embed_pattern(pattern, options) do
        {:ok, pattern, root} ->
          dir = path |> Path.dirname() |> Path.expand() |> then(&Path.expand(root, &1))
          glob = Path.join(dir, pattern <> ".{#{Enum.join(TemplateHazards.extensions(), ",")}}")
          compiled = GlobEx.compile!(glob)

          in_sources =
            igniter.rewrite
            |> Rewrite.sources()
            |> Enum.map(&Source.get(&1, :path))
            |> Enum.filter(&GlobEx.match?(compiled, Path.expand(&1)))

          on_disk = glob |> Path.wildcard() |> Enum.map(&Path.relative_to_cwd/1)
          read_all(igniter, Enum.sort(Enum.uniq(in_sources ++ on_disk)))

        :computed ->
          :unreadable
      end
    end

    # A LiveView or LiveComponent renders `page_live.html.heex` beside
    # `page_live.ex` when it has no render/1; read it for any module, since
    # a site's own `use` macro may set one up
    defp colocated_templates(igniter, path) do
      root = Path.rootname(path)

      [root <> ".html.heex", root <> ".html.leex"]
      |> Enum.filter(&(Rewrite.has_source?(igniter.rewrite, &1) or File.exists?(&1)))
      |> then(&read_all(igniter, &1, :allow_none))
    end

    # `{:ok, [{path, text}]}` from the sources, or else from disk; an
    # `embed_templates` that finds nothing, or a template that cannot be
    # read, is :unreadable
    defp read_all(igniter, paths, none \\ :unreadable)
    defp read_all(_igniter, [], :unreadable), do: :unreadable

    defp read_all(igniter, paths, _none) do
      Enum.reduce_while(paths, {:ok, []}, fn template, {:ok, read} ->
        case read_template(igniter, template) do
          {:ok, text} -> {:cont, {:ok, read ++ [{template, text}]}}
          :error -> {:halt, :unreadable}
        end
      end)
    end

    defp read_template(igniter, template) do
      if Rewrite.has_source?(igniter.rewrite, template) do
        {:ok, igniter.rewrite |> Rewrite.source!(template) |> Source.get(:content)}
      else
        with {:error, _} <- File.read(template), do: :error
      end
    end

    defp readable({:ok, templates}), do: templates
    defp readable(:unreadable), do: []

    # The line of the first template this task cannot read: an
    # `embed_templates` whose pattern or root is computed, or that is called
    # remotely, `use Phoenix.View`, `use Phoenix.Template` or
    # `Phoenix.Template.compile_all`, `use …, :view`, or Surface's `~F`
    defp opaque_templates(_content, _templates, :unreadable), do: 1

    defp opaque_templates(content, templates, _colocated) do
      {:ok, ast} = Sourceror.parse_string(content)
      ast = LexicalAliases.annotate(ast)

      {_ast, line} =
        Macro.prewalk(ast, nil, fn
          node, nil -> {node, if(opaque_template?(node, templates), do: node_line(node))}
          node, line -> {node, line}
        end)

      line
    end

    @eex_compilers [:function_from_string, :function_from_file, :compile_string, :compile_file]

    defp opaque_template?({:embed_templates, _, [pattern | options]}, templates),
      do: templates.(pattern, options) == :unreadable

    defp opaque_template?({{:., _, [remote, name]}, _, _}, _templates) when name in @eex_compilers,
      do: LexicalAliases.module(remote) == EEx

    defp opaque_template?({name, _, args}, _templates) when name in @eex_compilers and is_list(args), do: true
    defp opaque_template?(node, _templates), do: opaque_template?(node)

    defp opaque_template?({{:., _, [_remote, :embed_templates]}, _, _}), do: true
    defp opaque_template?({:sigil_F, _, _}), do: true
    defp opaque_template?({:use, _, [_target, {:__block__, _, [:view]}]}), do: true
    defp opaque_template?({:use, _, [_target, :view]}), do: true

    defp opaque_template?({:use, _, [target | _]}), do: LexicalAliases.module(target) in [Phoenix.View, Phoenix.Template]

    defp opaque_template?({{:., _, [remote, :compile_all]}, _, _}),
      do: LexicalAliases.module(remote) == Phoenix.Template

    defp opaque_template?(_node), do: false

    defp node_line({_, meta, _}) when is_list(meta), do: meta[:line] || 1
    defp node_line({{_, meta, _}, _, _}), do: meta[:line] || 1
    defp node_line(_node), do: 1

    # Where a template the file holds or embeds names one of `shorts` (the
    # aliases the rewrite changes) as code would: followed by `.`, `{`, `}`,
    # `)`, `,`, `]`, `<-` or `%>`. The raw text, comments, strings and
    # attributes included, so a template the code scan misreads cannot hide
    # a use; prose (`Upload a file`) does not count. `{where, name}`.
    @raw_sigils [:sigil_H, :sigil_L, :sigil_E, :sigil_h, :sigil_l, :sigil_e]

    defp template_mention(content, shorts, templates, colocated) do
      names = shorts |> Enum.uniq() |> Enum.map_join("|", &Regex.escape(Atom.to_string(&1)))
      regex = Regex.compile!("(?<![\\w.@:\\-])(#{names})(?=[.{}),\\]]|\\s*(?:<-|%>|\\}|\\)))")
      {:ok, ast} = Sourceror.parse_string(content)
      ast = LexicalAliases.annotate(ast)

      {_ast, texts} =
        Macro.prewalk(ast, [], fn
          {sigil, meta, [{:<<>>, _, parts} | _]} = node, texts when sigil in @raw_sigils ->
            first_line = meta[:line] + if(meta[:delimiter] in [~s("""), ~s(''')], do: 1, else: 0)
            {node, [{nil, first_line, parts |> Enum.filter(&is_binary/1) |> Enum.join()} | texts]}

          {:embed_templates, _, [pattern | options]} = node, texts ->
            {node, Enum.reverse(for({path, text} <- readable(templates.(pattern, options)), do: {path, 1, text}), texts)}

          node, texts ->
            {node, texts}
        end)

      texts
      |> Enum.reverse()
      |> Enum.concat(for {path, text} <- colocated, do: {path, 1, text})
      |> Enum.find_value(&mention(&1, regex))
    end

    defp mention({path, first_line, text}, regex) do
      case Regex.run(regex, text, return: :index, capture: :first) do
        [{at, length}] ->
          line = first_line + (text |> binary_part(0, at) |> :binary.matches("\n") |> length())
          {{path, line}, binary_part(text, at, length)}

        nil ->
          nil
      end
    end

    defp new_name([_ | _] = parts, renamed) do
      module = Module.concat(parts)
      Map.get(renamed, module, module)
    end

    defp new_name(_parts, _renamed), do: nil

    defp segment_name({name, _, _}), do: name
    defp segment_name(name), do: name

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

    # `{position, short} => entry` for the aliases declared at the top of
    # `body`, and those of the enclosing modules. A use finds its entry by
    # the declaration it comes from (`:alias_binding`), so an alias declared
    # again, in a function or later in the module, keeps its own uses. The
    # entry of a renamed module says what happens to its declaration and
    # its uses, from how they are used everywhere it reaches, nested modules
    # included:
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
        Enum.map(Map.keys(outer.entries), &elem(&1, 1)) ++
          Enum.map(alias_declarations(body), & &1.short) ++ nested_module_names(body)

      entries =
        direct
        |> alias_declarations()
        |> Enum.reduce(outer.entries, fn declaration, entries ->
          entry = alias_entry(declaration, body, outer.renamed, taken)
          Map.put(entries, {declaration.position, declaration.short}, entry)
        end)

      %{renamed: outer.renamed, entries: entries, direct: MapSet.new(direct, &node_position/1)}
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

    # An alias relative to another (`alias Meta.HTML`, `alias Meta.{HTML}`)
    # is followed through that one's entry, not renamed on its own
    defp alias_entry(%{module: module, relative?: relative?} = declaration, body, renamed, taken) do
      new = if not relative?, do: renamed[module]
      mode = if new, do: alias_mode(declaration, new, alias_uses(body, declaration), taken)
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

    # Every alias in `ast`: `%{module, short, as, base, position, relative?}`;
    # `base` is the brace alias's prefix, nil for a plain alias, and
    # `relative?` whether its first segment is itself an alias's
    defp alias_declarations(ast) do
      {_ast, declarations} =
        Macro.prewalk(ast, [], fn
          {:alias, _, [{:__aliases__, meta, parts} | options]} = node, acc ->
            relative? = not is_nil(meta[:alias_binding])
            {node, declaration(alias_module(parts), alias_as(options), {nil, node, relative?}, acc)}

          {:alias, _, [{{:., _, [{:__aliases__, meta, base}, :{}]}, _, children}]} = node, acc ->
            relative? = not is_nil(meta[:alias_binding])
            {node, Enum.reduce(children, acc, &braced_declaration(&1, {base, node, relative?}, &2))}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(declarations)
    end

    defp braced_declaration({:__aliases__, _, parts}, {base, _, _} = from, acc),
      do: declaration(alias_module(base ++ parts), nil, from, acc)

    defp braced_declaration(_child, _from, acc), do: acc

    defp declaration(nil, _as, _from, acc), do: acc

    defp declaration(module, as, {base, node, relative?}, acc) do
      [
        %{
          module: module,
          as: as,
          short: as || short_name(module),
          base: base,
          position: node_position(node),
          relative?: relative?
        }
        | acc
      ]
    end

    defp alias_as([options]) when is_list(options) do
      Enum.find_value(options, fn
        {{:__block__, _, [:as]}, {:__aliases__, _, [as]}} -> as
        _ -> nil
      end)
    end

    defp alias_as(_options), do: nil

    # How the names that come from `declaration` are used: `:bare` on their
    # own (`Meta`, `%Meta{}`, `Meta.changeset(…)`), `:nested` with more
    # segments (`Meta.HTML`, `alias Meta.HTML`, `alias Meta.{HTML}`)
    defp alias_uses(body, %{position: position, short: short}) do
      {_ast, uses} =
        Macro.prewalk(body, MapSet.new(), fn
          {:alias, _, [{:__aliases__, meta, [^short, _ | _]} | _]}, uses ->
            {:ok, if(meta[:alias_binding] == position, do: MapSet.put(uses, :nested), else: uses)}

          {:alias, _, [{{:., _, [{:__aliases__, meta, [^short | _]}, :{}]}, _, _}]}, uses ->
            {:ok, if(meta[:alias_binding] == position, do: MapSet.put(uses, :nested), else: uses)}

          {:alias, _, _}, uses ->
            {:ok, uses}

          {:__aliases__, meta, [^short | rest]} = node, uses ->
            cond do
              meta[:alias_binding] != position -> {node, uses}
              rest == [] -> {node, MapSet.put(uses, :bare)}
              true -> {node, MapSet.put(uses, :nested)}
            end

          node, uses ->
            {node, uses}
        end)

      uses
    end

    # The entry of the declaration a name comes from
    defp binding_entry({:__aliases__, meta, [first | _]}, ctx), do: ctx.entries[{meta[:alias_binding], first}]

    ## Patches

    defp patch({:alias, _, _} = node, ctx, acc) do
      if MapSet.member?(ctx.direct, node_position(node)),
        do: {:ok, patch_alias(node, ctx, acc)},
        else: {:ok, leave_alias(node, ctx, acc)}
    end

    defp patch({:match, [{:scope_alias, scope} | _] = meta, [verb, path, plug | rest]}, ctx, acc) do
      {{:match, meta, [verb, path | rest]}, leave_match_route(scope, plug, meta, ctx, acc)}
    end

    defp patch({verb, [{:scope_alias, scope} | _] = meta, [path, {:__aliases__, plug_meta, _} = plug | rest]}, ctx, acc) do
      module = RenamedModules.scoped_module(scope, plug)

      acc =
        case {module && ctx.renamed[module], plug_meta[:alias_binding]} do
          {nil, _binding} -> acc
          {new, nil} -> patch_scoped_route(verb, meta, plug, rest, {scope, module, new}, acc)
          {new, _binding} -> leave_scoped_route(module, meta, new, acc)
        end

      {{verb, meta, [path | rest]}, acc}
    end

    # A name no alias reaches is renamed in full; one that comes from an
    # alias follows what its alias does
    defp patch({:__aliases__, meta, [_ | rest] = parts} = node, ctx, {patches, left} = acc) do
      change =
        if is_nil(meta[:alias_binding]),
          do: (new = ctx.renamed[alias_module(parts)]) && full_name(parts, new),
          else: Enum.all?(rest, &is_atom/1) && alias_use_change(binding_entry(node, ctx), rest)

      if is_binary(change),
        do: {node, {[module_patch(node, change) | patches], left}},
        else: {node, acc}
    end

    defp patch(node, _ctx, acc), do: {node, acc}

    defp patch_alias(node, ctx, acc) do
      if relative_alias?(node),
        do: patch_relative_alias(node, ctx, acc),
        else: patch_plain_alias(node, ctx, acc)
    end

    defp relative_alias?({:alias, _, [{:__aliases__, meta, _} | _]}), do: not is_nil(meta[:alias_binding])

    defp relative_alias?({:alias, _, [{{:., _, [{:__aliases__, meta, _}, :{}]}, _, _}]}),
      do: not is_nil(meta[:alias_binding])

    defp relative_alias?(_node), do: false

    # A relative alias (`alias Meta.HTML` after `alias Brando.Meta`) follows
    # what its first segment does
    defp patch_relative_alias(
           {:alias, _, [{:__aliases__, _, [_ | [_ | _] = rest]} = target | _]},
           ctx,
           {patches, left} = acc
         ) do
      case Enum.all?(rest, &is_atom/1) && alias_use_change(binding_entry(target, ctx), rest) do
        change when is_binary(change) -> {[module_patch(target, change) | patches], left}
        _ -> acc
      end
    end

    # A brace alias under another alias (`alias Meta.{HTML}`) gets its
    # prefix spelled out as that alias's uses do
    defp patch_relative_alias(
           {:alias, _, [{{:., _, [{:__aliases__, _, [_ | rest]} = base, :{}]}, _, _}]},
           ctx,
           {patches, left} = acc
         ) do
      case Enum.all?(rest, &is_atom/1) && binding_entry(base, ctx) do
        %{mode: mode, module: module} when mode in [:follow, :rename, :rename_as] ->
          {[module_patch(base, inspect(Module.concat([module | rest]))) | patches], left}

        _ ->
          acc
      end
    end

    defp patch_relative_alias(_node, _ctx, acc), do: acc

    defp patch_plain_alias({:alias, _, [{:__aliases__, _, parts} = target | options]} = node, ctx, {patches, left} = acc) do
      case alias_module(parts) && ctx.entries[{node_position(node), alias_as(options) || short_name(alias_module(parts))}] do
        %{new: new, mode: mode} = entry when mode in [:follow, :rename] ->
          {[module_patch(target, full_name(parts, new)) | patches], changed_shorts(entry) ++ left}

        %{new: new, mode: :rename_as, short: short} = entry ->
          {[module_patch(target, "#{full_name(parts, new)}, as: #{short}") | patches], changed_shorts(entry) ++ left}

        _ ->
          acc
      end
    end

    # A brace alias, child by child
    defp patch_plain_alias({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, ctx, acc) do
      Enum.reduce(children, acc, &patch_braced(&1, {base, node_position(node)}, ctx, &2))
    end

    defp patch_plain_alias(_node, _ctx, acc), do: acc

    # An alias inside a function or block: reported when it names a renamed
    # module, and left as it is
    defp leave_alias({:alias, meta, _} = node, ctx, {patches, left} = acc) do
      case node
           |> List.wrap()
           |> alias_declarations()
           |> Enum.find(&(not &1.relative? and Map.has_key?(ctx.renamed, &1.module))) do
        nil -> acc
        %{module: module} -> {patches, [{:alias_in_block, module, meta[:line]} | left]}
      end
    end

    # The names a renamed alias declaration changes the meaning of: its
    # short name, and the new one it takes. As hazards for any template in
    # the project: both names when the short name changes, and otherwise
    # the modules under the old name that did not move (`Meta.HTML`)
    defp changed_shorts(%{mode: :follow, short: short, new: new}) do
      new_short = short_name(new)
      [{:short, short}, {:short, new_short}, {:hazard, Atom.to_string(short)}, {:hazard, Atom.to_string(new_short)}]
    end

    defp changed_shorts(%{short: short, module: module}) do
      [{:short, short} | for(child <- RenamedModules.unmoved_children(module), do: {:hazard, "#{short}.#{child}"})]
    end

    # `{line, token, [{template, line}]}` when a template in the project
    # uses a name the rewrite changes and the file can render templates:
    # the template may be this module's, wherever it lives
    defp project_template(content, path, hazards, corpus, igniter) do
      with {token, [_ | _] = uses} <-
             Enum.find_value(hazards, fn token -> {token, TemplateHazards.uses(corpus, token, path)} |> nonempty() end),
           line when not is_nil(line) <- renders_templates(content, path, igniter) do
        {line, token, uses}
      else
        _ -> nil
      end
    end

    defp nonempty({_token, []}), do: nil
    defp nonempty(found), do: found

    defp renders_templates(content, path, igniter) do
      {:ok, ast} = Sourceror.parse_string(content)
      TemplateHazards.renders_templates(LexicalAliases.annotate(ast)) || sibling_template(path, igniter)
    end

    # A template file of any name in the same directory
    defp sibling_template(path, igniter) do
      dir = Path.dirname(path)

      in_sources =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&Source.get(&1, :path))
        |> Enum.filter(&(Path.dirname(&1) == dir))

      on_disk = for file <- ls(dir), do: Path.join(dir, file)
      if Enum.any?(in_sources ++ on_disk, &TemplateHazards.template_file?/1), do: 1
    end

    defp ls(dir) do
      case File.ls(dir) do
        {:ok, files} -> files
        {:error, _} -> []
      end
    end

    defp alias_use_change(%{mode: :follow, new: new}, []), do: Atom.to_string(short_name(new))

    defp alias_use_change(%{mode: mode, module: module}, [_ | _] = rest) when mode in [:follow, :rename, :rename_as],
      do: inspect(Module.concat([module | rest]))

    defp alias_use_change(_entry, _rest), do: nil

    defp patch_braced({:__aliases__, _, parts} = child, {base, position}, ctx, {patches, left} = acc) do
      module = alias_module(base ++ parts)

      case module && ctx.entries[{position, short_name(module)}] do
        %{module: ^module, mode: mode, new: new} = entry when mode in [:follow, :rename] ->
          {[module_patch(child, Enum.join(relative_parts(base, new), ".")) | patches], changed_shorts(entry) ++ left}

        %{module: ^module, mode: :left} ->
          {patches, [{:braced, module} | left]}

        _ ->
          acc
      end
    end

    defp patch_braced(_child, _from, _ctx, acc), do: acc

    @http_verbs [:get, :post, :put, :patch, :delete, :options, :head]

    # Relative to the scope when the new name is under its alias. Otherwise
    # the full name and `alias: false`, inserted after the last argument so
    # the route keeps its layout and comments; only for an HTTP verb whose
    # options, if any, are a plain keyword list without `alias:`.
    defp patch_scoped_route(verb, meta, plug, rest, {scope, module, new}, {patches, left} = acc) do
      cond do
        verb not in @http_verbs ->
          leave_scoped_route(module, meta, new, acc)

        new_parts = relative_parts(scope, new) ->
          {[module_patch(plug, Enum.join(new_parts, ".")) | patches], left}

        insert_at = alias_false_position(rest) ->
          insert = Sourceror.Patch.new(%Sourceror.Range{start: insert_at, end: insert_at}, ", alias: false", false)
          {[insert, module_patch(plug, inspect(new)) | patches], left}

        true ->
          leave_scoped_route(module, meta, new, acc)
      end
    end

    # `match` and the other forms the task does not rewrite: reported
    defp leave_match_route(scope, plug, meta, ctx, acc) do
      module = RenamedModules.scoped_module(scope, plug)

      case module && ctx.renamed[module] do
        nil -> acc
        new -> leave_scoped_route(module, meta, new, acc)
      end
    end

    defp leave_scoped_route(module, meta, new, {patches, left}),
      do: {patches, [{:route, module, new, meta[:line]} | left]}

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

    # The new name, with the old one's `Elixir.` prefix if it had one
    defp full_name([:"Elixir" | _], new), do: "Elixir." <> inspect(new)
    defp full_name(_parts, new), do: inspect(new)

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

        {:opaque_templates, line}, igniter ->
          Igniter.add_warning(igniter, """
          #{path}:#{line} names modules renamed in 0.55, and has templates this task cannot read \
          (a computed or remote `embed_templates`, Phoenix.View, Phoenix.Template or Surface's ~F), \
          so the file is unchanged: a template may use an alias it would rename. Replace the old \
          names yourself; they keep working, with a warning, until 0.57.
          """)

        {:project_template, {line, token, uses}}, igniter ->
          listed = uses |> Enum.take(5) |> Enum.map_join(", ", fn {template, at} -> "#{template}:#{at}" end)
          more = if length(uses) > 5, do: " and #{length(uses) - 5} more", else: ""

          Igniter.add_warning(igniter, """
          #{path}:#{line} left unchanged: a template in this project uses `#{token}`; check whether it \
          belongs to this module and rename it by hand. Renaming the modules renamed in 0.55 here would \
          change what `#{token}` means to a template compiled into it. Templates: #{listed}#{more}. \
          The old names keep working, with a warning, until 0.57.
          """)

        {:template_mention, {{template, line}, name}}, igniter ->
          where = if template, do: "#{template}:#{line}, a template #{path} embeds,", else: "#{path}:#{line}"

          Igniter.add_warning(igniter, """
          #{where} names modules renamed in 0.55: its template uses #{name}, an alias this task \
          would rename, so #{path} is unchanged. Use the new names there and in its templates \
          yourself; the old names keep working, with a warning, until 0.57.
          """)

        {:changed_meaning, line}, igniter ->
          Igniter.add_warning(igniter, """
          #{path}:#{line} names modules renamed in 0.55, but rewriting them would change which module \
          a name there, or in a template it embeds, refers to, so the file is unchanged. `mix brando.doctor` lists the old names to \
          replace; the old names keep working, with a warning, until 0.57.
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
