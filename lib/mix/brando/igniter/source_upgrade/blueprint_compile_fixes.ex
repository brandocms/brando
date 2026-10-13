if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.BlueprintCompileFixes do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Blueprint declarations that compiled on 0.54 and that 0.55 refuses:
    #
    #   * an `identifier` on an embedded Blueprint (`data_layer :embedded`),
    #     which identifies nothing: written `identifier false`;
    #   * `default_srcset:` in an asset config, which 0.53 and 0.54 ignored
    #     there (it is a `Brando.Images` setting): written as the asset's
    #     `srcset: %{default: …}`, or removed beside a `srcset:`, which the
    #     asset used.
    #
    # Run it before the other Blueprint rewrites, so the lines it reports are
    # the file's.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Mix.Brando.Igniter.SourceUpgrade.ModuleScope
    alias Rewrite.Source
    alias Sourceror.Zipper

    @scopes [:def, :defp, :defmacro, :defmacrop, :fn]

    @srcset_note """
    `default_srcset` was never an asset config field, and Brando ignored it
    there: the asset used its `srcset:`, or the default config's. Now the list
    applies to the asset; check that each size it names is in its `sizes`.
    """

    @doc "Rewrites both, noting each change with file and line."
    def rewrite(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)

      {igniter, changes} =
        Enum.reduce(blueprints, {igniter, []}, fn module, {igniter, changes} ->
          {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
          path = Source.get(source, :path)

          case findings(Zipper.subtree(zipper)) do
            [] ->
              {igniter, changes}

            found ->
              igniter = ProjectModule.find_and_update_module!(igniter, module, &update_body/1)

              {igniter, changes ++ Enum.map(found, fn {line, text} -> "#{path}:#{line}: #{text}" end)}
          end
        end)

      notice(igniter, changes)
    end

    # `{line, change}` for what `update/1` changes.
    defp findings(zipper) do
      identifiers =
        for identifier <- embedded_identifiers(zipper),
            do: {line(identifier), "`identifier false` on an embedded Blueprint"}

      srcsets =
        for {key, sibling_srcset?} <- default_srcsets(zipper) do
          if sibling_srcset?,
            do: {line(key), "`default_srcset:` removed; the `srcset:` beside it stays"},
            else: {line(key), "`default_srcset:` is now `srcset: %{default: …}`"}
        end

      Enum.sort(identifiers ++ srcsets)
    end

    # Within the module's body: the file may hold other modules.
    defp update_body(zipper), do: Common.within(zipper, &{:ok, update(&1)})

    # `zipper` is the module's body, as a subtree: the file may hold other
    # modules.
    defp update(zipper) do
      identifier_lines = zipper |> embedded_identifiers() |> MapSet.new(&line/1)
      srcset_lines = zipper |> default_srcsets() |> MapSet.new(fn {key, _sibling_srcset?} -> line(key) end)

      Zipper.traverse(zipper, &update_node(&1, identifier_lines, srcset_lines))
    end

    defp update_node(zipper, identifier_lines, srcset_lines) do
      case Zipper.node(zipper) do
        {:identifier, meta, [_template]} = node ->
          if MapSet.member?(identifier_lines, line(node)),
            do: Zipper.replace(zipper, {:identifier, meta, [{:__block__, [], [false]}]}),
            else: zipper

        node ->
          with {:ok, pairs} <- pairs(node),
               {key, _value} <- default_srcset(pairs),
               true <- MapSet.member?(srcset_lines, line(key)) do
            Zipper.replace(zipper, rewrite_pairs(node, pairs))
          else
            _ -> zipper
          end
      end
    end

    ## Embedded identifiers

    defp embedded_identifiers(zipper) do
      if embedded?(zipper) do
        zipper
        |> ModuleScope.find_all(&(CodeFunction.function_call?(&1, :identifier, 1) and declaration?(&1)))
        |> Enum.map(&call_node/1)
        |> Enum.reject(fn {:identifier, _meta, [template]} -> literal(template) in [false, nil] end)
      else
        []
      end
    end

    defp embedded?(zipper) do
      zipper
      |> ModuleScope.find_all(&(CodeFunction.function_call?(&1, :data_layer, 1) and declaration?(&1)))
      |> Enum.any?(&embedded_layer?(call_node(&1)))
    end

    defp embedded_layer?({:data_layer, _, [layer]}), do: literal(layer) == :embedded
    defp embedded_layer?(_node), do: false

    defp call_node(zipper), do: zipper |> Common.maybe_move_to_single_child_block() |> Zipper.node()

    # A Blueprint declaration, not a call inside a function.
    defp declaration?(zipper) do
      case Zipper.up(zipper) do
        nil -> true
        parent -> not match?({scope, _, _} when scope in @scopes, Zipper.node(parent)) and declaration?(parent)
      end
    end

    ## default_srcset

    # `{key_node, sibling_srcset?}` of each `default_srcset:` in an asset's
    # `cfg:`: given inline, or as a module attribute the module defines.
    defp default_srcsets(zipper) do
      {inline, attributes} =
        zipper
        |> ModuleScope.find_all(&CodeFunction.function_call?(&1, :asset, 3))
        |> Enum.flat_map(&asset_cfg(call_node(&1)))
        |> Enum.split_with(&(not match?({:attribute, _name}, &1)))

      attribute_names = for {:attribute, name} <- attributes, do: name

      attribute_values =
        for attribute <- ModuleScope.find_all(zipper, &match?({:@, _, [{_name, _, [_value]}]}, Zipper.node(&1))),
            {:@, _, [{name, _, [value]}]} = Zipper.node(attribute),
            name in attribute_names,
            do: value

      for config <- inline ++ attribute_values,
          {:ok, pairs} <- [config |> unwrap() |> pairs()],
          {key, _value} <- [default_srcset(pairs)],
          do: {key, Enum.any?(pairs, &(key(&1) == :srcset))}
    end

    defp asset_cfg({:asset, _, [_name, _type, options]}) do
      case options |> unwrap() |> pairs() do
        {:ok, pairs} ->
          for {key, value} <- pairs, literal(key) == :cfg, do: cfg_value(value)

        :error ->
          []
      end
    end

    defp asset_cfg(_node), do: []

    defp cfg_value({:@, _, [{name, _, context}]}) when is_atom(context), do: {:attribute, name}
    defp cfg_value(config), do: config

    defp unwrap({:__block__, _meta, [value]}) when is_list(value), do: value
    defp unwrap(value), do: value

    defp default_srcset(pairs), do: Enum.find(pairs, &(key(&1) == :default_srcset))

    defp rewrite_pairs(node, pairs) do
      pairs =
        if Enum.any?(pairs, &(key(&1) == :srcset)) do
          Enum.reject(pairs, &(key(&1) == :default_srcset))
        else
          Enum.map(pairs, fn
            {{:__block__, meta, [:default_srcset]}, value} ->
              {{:__block__, meta, [:srcset]}, {:%{}, [], [{{:__block__, [format: :keyword], [:default]}, value}]}}

            pair ->
              pair
          end)
        end

      put_pairs(node, pairs)
    end

    # The key/value pairs of a keyword list or a map literal.
    defp pairs({:%{}, _meta, pairs}) when is_list(pairs),
      do: if(Enum.all?(pairs, &pair?/1), do: {:ok, pairs}, else: :error)

    defp pairs([_ | _] = list), do: if(Enum.all?(list, &pair?/1), do: {:ok, list}, else: :error)
    defp pairs(_node), do: :error

    defp put_pairs({:%{}, meta, _pairs}, pairs), do: {:%{}, meta, pairs}
    defp put_pairs(list, pairs) when is_list(list), do: pairs

    defp pair?({{:__block__, _meta, [key]}, _value}) when is_atom(key), do: true
    defp pair?(_node), do: false

    defp key({{:__block__, _meta, [key]}, _value}), do: key

    defp literal({:__block__, _meta, [value]}), do: value
    defp literal(value), do: value

    defp line({{:__block__, meta, _}, _value}), do: meta[:line]
    defp line({_form, meta, _args}), do: meta[:line]

    defp notice(igniter, []), do: igniter

    defp notice(igniter, changes) do
      srcset? = Enum.any?(changes, &String.contains?(&1, "default_srcset"))

      Igniter.add_notice(igniter, """
      Blueprint declarations 0.55 no longer compiles were changed:

      #{Enum.map_join(changes, "\n", &("  " <> &1))}
      #{if srcset?, do: "\n" <> @srcset_note, else: ""}\
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.BlueprintCompileFixes do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
