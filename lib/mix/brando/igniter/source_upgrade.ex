if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Shared source-rewrite steps for the versioned `brando.migrate5x` tasks.
    #
    # Each step is idempotent: it matches legacy syntax or missing configuration
    # only, so a task may be rerun, and the tasks may be run in sequence
    # (`migrate54` then `migrate55`) on an application that starts before 0.54.
    # The tasks own the composition, notices, and warnings; this module owns
    # the rewrites.

    alias Expo.PluralForms
    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Config
    alias Igniter.Project.Module, as: ProjectModule
    alias Igniter.Refactors.Rename
    alias Mix.Brando.Igniter.FloristConfig
    alias Mix.Brando.Igniter.SourceUpgrade.BlueprintCatalogs
    alias Mix.Brando.Igniter.SourceUpgrade.Datasources
    alias Mix.Brando.Igniter.SourceUpgrade.NavigationItems
    alias Mix.Brando.Igniter.SourceUpgrade.PageVars
    alias Mix.Brando.Igniter.TemplateCode
    alias Rewrite.Source
    alias Sourceror.Zipper

    @font_source_extensions ~w(.css .eex .ex .exs .heex .leex .pcss .sass .scss)
    @font_vsn_regex ~r/(\.(?:woff2?|ttf|otf|eot))\?vsn=d\b/
    @live_view_package_regex ~r/("phoenix_live_view"\s*:\s*")[^"]+("\s*[,}])/
    @phx_digest_regex ~r/\bmix[\t ]+phx\.digest(?=[\t ]|$)/m
    @vite_sourcemap_regex ~r/(?<![\w$])(sourcemap\s*:\s*)true\b/
    @phoenix_live_view_fallback_version "1.2.13"

    @listing_core_components ~w(<.field <.i18n <.update_link <.url)

    @gettext_script_path "scripts/sync_gettext.sh"
    # The value of a .po header line: "Plural-Forms: nplurals=2; plural=(n != 1);\n"
    @plural_forms_header ~r/^"Plural-Forms:[ \t]*((?:[^"\\]|\\[^n])*?)[ \t]*(?:\\n)?"$/m

    ## Blueprint composition

    @doc """
    Applies `fun` to every module that `use Brando.Blueprint`.

    `fun` receives the module zipper and returns `{:ok, zipper}`,
    `{:warning, message}` or `{:error, message}` as
    `Igniter.Project.Module.find_and_update_module!/3` expects.
    """
    def rewrite_blueprints(igniter, fun) do
      {igniter, modules} = find_blueprints(igniter)

      Enum.reduce(modules, igniter, fn module, igniter ->
        ProjectModule.find_and_update_module!(igniter, module, fun)
      end)
    end

    @doc """
    Rewrites the Blueprint DSL surface that changed between 0.53 and 0.54.

    Every rewrite matches the legacy form only, so a Blueprint that already
    uses 0.54 syntax is returned unchanged.
    """
    def upgrade_054_blueprint(zipper) do
      villain_fields = collect_villain_fields(zipper)

      with {:ok, zipper} <- rewrite_legacy_datasources(zipper),
           {:ok, zipper} <- rewrite_traits(zipper),
           {:ok, zipper} <- rewrite_fieldsets(zipper),
           {:ok, zipper} <- rewrite_inputs_for(zipper),
           {:ok, zipper} <- rewrite_forms(zipper),
           {:ok, zipper} <- rewrite_listing_filters(zipper),
           {:ok, zipper} <- rewrite_listing_filter_keys(zipper),
           {:ok, zipper} <- rewrite_listing_actions(zipper),
           {:ok, zipper} <- rewrite_listing_selection_actions(zipper),
           {:ok, zipper} <- rewrite_listing_exports(zipper),
           {:ok, zipper} <- rewrite_listing_query(zipper),
           {:ok, zipper} <- rewrite_form_query(zipper),
           {:ok, zipper} <- rewrite_entries_sources(zipper),
           {:ok, zipper} <- rewrite_slug_source(zipper),
           {:ok, zipper} <- rewrite_json_ld_field(zipper),
           {:ok, zipper} <- rewrite_meta_field(zipper),
           {:ok, zipper} <- remove_villain_attributes(zipper),
           {:ok, zipper} <- add_villain_relations(zipper, villain_fields) do
        move_block_editor_inputs(zipper)
      end
    end

    # A 0.53 block editor was `input :data, :blocks` inside a fieldset. The
    # Villain attribute became a `:blocks` relation, and its editor is now the
    # form-level `blocks :blocks`, rendered below the tabs. An input whose name
    # is no relation, but whose relation name is, is moved there with its
    # options; a fieldset or tab left without content goes with it. Inputs an
    # earlier run of this task left behind are matched the same way.
    defp move_block_editor_inputs(zipper) do
      zipper = Zipper.topmost(zipper)

      renames =
        zipper
        |> Common.find_all(&CodeFunction.function_call?(&1, :input, [2, 3]))
        |> Enum.flat_map(&block_editor_rename(zipper, single_child(&1)))
        |> Map.new()

      if renames == %{} do
        {:ok, zipper}
      else
        Common.update_all_matches(zipper, &form_with_body?/1, fn form_zipper ->
          {:ok,
           form_zipper |> Common.maybe_move_to_single_child_block() |> Zipper.update(&move_form_block_inputs(&1, renames))}
        end)
      end
    end

    defp block_editor_rename(zipper, {:input, _, [name, type | _options]}) do
      with :blocks <- literal_atom_value(type),
           name when is_atom(name) and not is_nil(name) <- literal_atom_value(name),
           false <- relation_declared?(zipper, name),
           relation = villain_relation_name(name),
           true <- relation_declared?(zipper, relation) do
        [{name, relation}]
      else
        _ -> []
      end
    end

    defp block_editor_rename(_zipper, _node), do: []

    defp single_child(zipper), do: zipper |> Common.maybe_move_to_single_child_block() |> Zipper.node()

    defp form_with_body?(zipper) do
      CodeFunction.function_call?(zipper, :form) and match?({:ok, _}, do_body(single_child(zipper)))
    end

    defp move_form_block_inputs(form, renames) do
      {:ok, statements} = do_body(form)

      case strip_block_inputs(statements, renames) do
        {_statements, []} ->
          form

        {statements, moved} ->
          declared = for {:blocks, _, [name | _]} <- statements, do: literal_atom_value(name)

          editors =
            moved
            |> Enum.uniq_by(fn {name, _options} -> name end)
            |> Enum.reject(fn {name, _options} -> name in declared end)
            |> Enum.map(fn {name, options} -> {:blocks, [], [name | options]} end)

          {options, rest} = Enum.split_while(statements, &(not form_entity?(&1)))
          put_do_body(form, options ++ editors ++ rest)
      end
    end

    # Removes the block editor inputs named in `renames`, returning what is left
    # and the `{relation_ast, options}` of each removed input.
    defp strip_block_inputs(statements, renames) do
      {kept, moved} =
        Enum.map_reduce(statements, [], fn statement, moved ->
          case block_editor_input(statement, renames) do
            {:ok, editor} ->
              {[], moved ++ [editor]}

            :error ->
              strip_nested_block_inputs(statement, renames, moved)
          end
        end)

      {List.flatten(kept), moved}
    end

    defp strip_nested_block_inputs(statement, renames, moved) do
      with {:ok, body} <- do_body(statement),
           {body, [_ | _] = nested} <- strip_block_inputs(body, renames) do
        if Enum.any?(body, &form_entity?/1),
          do: {[put_do_body(statement, body)], moved ++ nested},
          else: {[], moved ++ nested}
      else
        _ -> {[statement], moved}
      end
    end

    defp block_editor_input({:input, _meta, [name, type | options]}, renames) do
      with :blocks <- literal_atom_value(type),
           {:ok, relation} <- Map.fetch(renames, literal_atom_value(name)) do
        {:ok, {{:__block__, [], [relation]}, options |> accepted_options() |> Enum.map(&without_position/1)}}
      else
        _ -> :error
      end
    end

    defp block_editor_input(_statement, _renames), do: :error

    # The options `blocks` accepts, out of an input's literal keyword list.
    # `warn_block_editor_options/1` names the rest.
    defp accepted_options([options]) do
      allowed = blocks_options()

      case Enum.filter(option_entries(options), fn {key, _value} -> literal_atom_value(key) in allowed end) do
        [] -> []
        kept -> [kept]
      end
    end

    defp accepted_options(_options), do: []

    defp option_entries(options) do
      Enum.filter(keyword_entries(options), &match?({_key, _value}, &1))
    rescue
      FunctionClauseError -> []
    end

    # Read from the forms DSL, so the list follows the entity's schema.
    defp blocks_options do
      Brando.Blueprint.Forms.Dsl.sections()
      |> Enum.flat_map(& &1.entities)
      |> Enum.find(&(&1.name == :form))
      |> Map.fetch!(:entities)
      |> Keyword.fetch!(:blocks)
      |> hd()
      |> Map.fetch!(:schema)
      |> Keyword.fetch!(:opts)
      |> Keyword.fetch!(:type)
      |> keyword_list_keys()
    end

    defp keyword_list_keys({:or, types}), do: Enum.flat_map(types, &keyword_list_keys/1)
    defp keyword_list_keys({:keyword_list, schema}), do: Keyword.keys(schema)
    defp keyword_list_keys(_type), do: []

    @doc """
    Warns, with file and line, about each option of a Villain block editor
    input (`input :data, :blocks, ...`) that the form-level `blocks` it
    becomes does not accept. `upgrade_054_blueprint/1` drops them, since
    `blocks` validates its options and the Blueprint would not compile.
    Run it before the Blueprint rewrite, which removes the Villain
    attributes the inputs are matched by.
    """
    def warn_block_editor_options(igniter) do
      {igniter, blueprints} = find_blueprints(igniter)
      allowed = blocks_options()

      {igniter, findings} =
        Enum.reduce(blueprints, {igniter, []}, fn module, {igniter, findings} ->
          {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
          {igniter, findings ++ dropped_options(zipper, Source.get(source, :path), allowed)}
        end)

      case findings do
        [] ->
          igniter

        findings ->
          Igniter.add_warning(igniter, """
          Block editor options that form-level `blocks` does not take were dropped
          when the editors moved there (it takes #{Enum.map_join(allowed, ", ", &"`#{&1}`")}):

          #{Enum.map_join(findings, "\n", &("  " <> &1))}
          """)
      end
    end

    defp dropped_options(zipper, path, allowed) do
      villain = zipper |> Common.find_all(&villain_attribute?/1) |> Enum.map(&villain_attribute_name/1)

      zipper
      |> Common.find_all(&CodeFunction.function_call?(&1, :input, 3))
      |> Enum.map(&single_child/1)
      |> Enum.filter(&(villain_block_input?(&1, villain) or block_editor_rename(zipper, &1) != []))
      |> Enum.flat_map(&dropped_input_options(&1, "#{path}:", allowed))
    end

    defp dropped_input_options({:input, meta, [_name, _type, options]}, location, allowed) do
      case option_entries(options) do
        [] ->
          ["#{location}#{meta[:line]}: options that are not a literal keyword list"]

        entries ->
          for {key, _value} <- entries,
              key = literal_atom_value(key),
              key not in allowed,
              do: "#{location}#{meta[:line]}: `#{key}`"
      end
    end

    defp villain_block_input?({:input, _, [name, type | _options]}, villain),
      do: literal_atom_value(type) == :blocks and literal_atom_value(name) in villain

    defp villain_block_input?(_node, _villain), do: false

    defp villain_attribute_name(attribute_zipper) do
      attribute_zipper |> Zipper.node() |> Sourceror.get_args() |> List.first() |> literal_atom!()
    end

    # Comments are printed by line, so a node moved up the file keeps none:
    # with its old lines, comments between the two places land inside it.
    @position_meta [:line, :column, :end_of_expression, :closing, :newlines, :leading_comments, :trailing_comments]

    defp without_position(ast) do
      Macro.prewalk(ast, fn
        {form, meta, args} when is_list(meta) -> {form, Keyword.drop(meta, @position_meta), args}
        node -> node
      end)
    end

    # The calls that give a tab, fieldset or form content; the rest are options.
    defp form_entity?({name, _, _}) when name in [:tab, :fieldset, :alert, :input, :inputs_for, :component, :blocks],
      do: true

    defp form_entity?(_statement), do: false

    defp do_body({_name, _meta, args}) when is_list(args) do
      case Enum.reverse(args) do
        [[{{:__block__, _, [:do]}, {:__block__, _, statements}}] | _] when is_list(statements) -> {:ok, statements}
        [[{{:__block__, _, [:do]}, statement}] | _] -> {:ok, [statement]}
        _ -> :error
      end
    end

    defp do_body(_node), do: :error

    defp put_do_body({name, meta, args}, statements) do
      [[{{:__block__, do_meta, [:do]}, body}] | arguments] = Enum.reverse(args)
      do_block = [{{:__block__, do_meta, [:do]}, {:__block__, block_meta(body), statements}}]
      {name, meta, Enum.reverse(arguments, [do_block])}
    end

    defp block_meta({:__block__, meta, statements}) when is_list(statements), do: meta
    defp block_meta(_statement), do: []

    defp rewrite_legacy_datasources(zipper) do
      if uses_legacy_datasource?(zipper) do
        with {:ok, zipper} <- rewrite_list_datasources(zipper),
             {:ok, zipper} <- rewrite_single_datasources(zipper),
             {:ok, zipper} <- rewrite_selection_datasources(zipper) do
          remove_use_datasource(zipper)
        end
      else
        {:ok, zipper}
      end
    end

    defp rewrite_single_datasources(zipper) do
      Common.update_all_matches(
        zipper,
        &single_datasource?(&1),
        fn zipper ->
          [key, get_callback] = zipper |> Zipper.node() |> Sourceror.get_args()
          get = capture_call(get_callback, [quote(do: to_string(__MODULE__)), quote(do: identifier)])

          new_datasource =
            quote do
              datasource unquote(key) do
                type :single

                get fn identifier ->
                  unquote(get)
                end
              end
            end

          {:ok, Common.replace_code(zipper, new_datasource)}
        end
      )
    end

    defp rewrite_list_datasources(zipper) do
      Common.update_all_matches(
        zipper,
        &list_datasource?(&1),
        fn zipper ->
          [key, list_callback] = zipper |> Zipper.node() |> Sourceror.get_args()

          new_datasource =
            quote do
              datasource unquote(key) do
                type :list
                list unquote(list_callback)
              end
            end

          {:ok, Common.replace_code(zipper, new_datasource)}
        end
      )
    end

    defp rewrite_selection_datasources(zipper) do
      Common.update_all_matches(
        zipper,
        &selection_datasource?(&1),
        fn zipper ->
          [key, list_callback, get_callback] = zipper |> Zipper.node() |> Sourceror.get_args()

          new_datasource =
            quote do
              datasource unquote(key) do
                type :selection
                list unquote(list_callback)
                get unquote(get_callback)
              end
            end

          {:ok, Common.replace_code(zipper, new_datasource)}
        end
      )
    end

    defp remove_use_datasource(zipper), do: Datasources.remove_use(zipper, &use_datasource?/1)

    defp rewrite_listing_filters(zipper), do: rewrite_keyword_collection(zipper, :filters, :filter)

    defp rewrite_listing_actions(zipper) do
      with {:ok, zipper} <- rewrite_keyword_collection(zipper, :actions, :action) do
        Common.update_all_matches(zipper, &legacy_actions_with_options?/1, fn zipper ->
          {:actions, metadata, [items, options]} = Zipper.node(zipper)

          replacement =
            [keyword_collection_code(items, :action, metadata), extract_macros_from_ast(options)]
            |> Enum.reject(&(&1 == ""))
            |> Enum.join("\n")

          {:ok, Common.replace_code(zipper, replacement)}
        end)
      end
    end

    defp rewrite_listing_selection_actions(zipper) do
      rewrite_keyword_collection(zipper, :selection_actions, :selection_action)
    end

    defp rewrite_listing_exports(zipper) do
      Common.update_all_matches(zipper, &legacy_listing_export?/1, fn zipper ->
        [name, options] = zipper |> Zipper.node() |> Sourceror.get_args()

        replacement = "export #{Sourceror.to_string(name)} do\n#{extract_macros_from_ast(options)}\nend"
        {:ok, Common.replace_code(zipper, replacement)}
      end)
    end

    defp rewrite_listing_filter_keys(zipper) do
      Common.update_all_matches(zipper, &listing_filter_with_legacy_key?/1, fn zipper ->
        case CodeFunction.move_to_nth_argument(zipper, 0) do
          {:ok, options_zipper} ->
            options = options_zipper |> Zipper.node() |> normalize_filter_key()
            {:ok, options_zipper |> Zipper.replace(options) |> Zipper.up()}

          :error ->
            {:ok, zipper}
        end
      end)
    end

    defp rename_filter_key({{:__block__, metadata, [:filter]}, value}) do
      {{:__block__, metadata, [:key]}, value}
    end

    defp rename_filter_key({:filter, value}), do: {:key, value}
    defp rename_filter_key(other), do: other

    defp normalize_filter_key(options) do
      if Enum.any?(options, &keyword_key?(&1, :key)) do
        Enum.reject(options, &keyword_key?(&1, :filter))
      else
        Enum.map(options, &rename_filter_key/1)
      end
    end

    defp keyword_key?({{:__block__, _, [key]}, _value}, key), do: true
    defp keyword_key?({key, _value}, key), do: true
    defp keyword_key?(_option, _key), do: false

    defp rewrite_keyword_collection(zipper, collection_name, item_name) do
      Common.update_all_matches(
        zipper,
        &CodeFunction.function_call?(&1, collection_name, 1),
        fn zipper ->
          {:ok, rewrite_keyword_collection_call(zipper, item_name)}
        end
      )
    end

    defp rewrite_keyword_collection_call(zipper, item_name) do
      case Zipper.node(zipper) do
        {_collection_name, metadata, [{:__block__, _, [items]}]} when is_list(items) ->
          replacement = keyword_collection_code(items, item_name, metadata)
          Common.replace_code(zipper, replacement)

        _other ->
          zipper
      end
    end

    defp keyword_collection_code({:__block__, _, [items]}, item_name, metadata)
         when is_list(items) do
      keyword_collection_code(items, item_name, metadata)
    end

    defp keyword_collection_code(items, item_name, metadata) when is_list(items) do
      Enum.map_join(items, "\n", &keyword_item_call(&1, item_name, metadata))
    end

    defp keyword_item_call({:__block__, _, [keyword_tuples]}, item_name, metadata)
         when is_list(keyword_tuples) do
      Sourceror.to_string({item_name, metadata, [keyword_tuples]})
    end

    defp add_villain_relations(zipper, villain_fields) do
      missing_fields = Enum.reject(villain_fields, &relation_declared?(zipper, &1))
      add_missing_relations(zipper, missing_fields)
    end

    def add_listing_component_imports(zipper) do
      zipper = Zipper.topmost(zipper)

      if listing_component_declared?(zipper) do
        source = zipper |> Zipper.node() |> Sourceror.to_string()

        import_specs =
          []
          |> maybe_add_listing_import(
            Enum.any?(@listing_core_components, &String.contains?(source, &1)) or
              String.contains?(source, ["<.cover", "<.children_button"]),
            Brando.Blueprint.Listings.Components.Core,
            nil
          )
          |> maybe_add_listing_import(
            String.contains?(source, "<.cover"),
            Brando.Blueprint.Listings.Components.Cover,
            "only: [cover: 1]"
          )
          |> maybe_add_listing_import(
            String.contains?(source, "<.children_button"),
            Brando.Blueprint.Listings.Components.Children,
            "only: [children_button: 1]"
          )
          |> Enum.reject(fn {module, _opts} -> module_imported?(zipper, module) end)

        case import_specs do
          [] -> {:ok, zipper}
          imports -> add_listing_imports(zipper, imports)
        end
      else
        {:ok, zipper}
      end
    end

    defp add_listing_imports(zipper, imports) do
      code =
        Enum.map_join(imports, "\n", fn
          {module, nil} -> "import #{inspect(module)}"
          {module, opts} -> "import #{inspect(module)}, #{opts}"
        end)

      with {:ok, module_body} <-
             Igniter.Code.Module.move_to_module_using(zipper, Brando.Blueprint),
           {:ok, use_zipper} <-
             Igniter.Code.Module.move_to_use(module_body, Brando.Blueprint) do
        {:ok, Common.add_code(use_zipper, code, placement: :after)}
      else
        :error -> {:warning, "Could not place explicit listing component imports"}
      end
    end

    defp maybe_add_listing_import(imports, true, module, opts), do: imports ++ [{module, opts}]
    defp maybe_add_listing_import(imports, false, _module, _opts), do: imports

    defp listing_component_declared?(zipper) do
      zipper
      |> Common.find_all(&CodeFunction.function_call?(&1, :component, 1))
      |> Enum.any?()
    end

    defp module_imported?(zipper, module) do
      zipper
      |> Common.find_all(fn import_zipper ->
        CodeFunction.function_call?(import_zipper, :import) and
          CodeFunction.argument_equals?(import_zipper, 0, module)
      end)
      |> Enum.any?()
    end

    defp add_missing_relations(zipper, []), do: {:ok, zipper}

    defp add_missing_relations(zipper, missing_fields) do
      case CodeFunction.move_to_function_call_in_current_scope(zipper, :relations, 1) do
        :error ->
          add_relations_block(zipper, missing_fields)

        {:ok, relations_zipper} ->
          add_to_relations_block(relations_zipper, missing_fields)
      end
    end

    defp add_relations_block(zipper, fields) do
      code = "relations do\n#{villain_relations_code(fields)}\nend\n"
      {:ok, Common.add_code(zipper, code)}
    end

    defp add_to_relations_block(relations_zipper, fields) do
      case Common.move_to_do_block(relations_zipper) do
        {:ok, block_zipper} ->
          {:ok, Common.add_code(block_zipper, villain_relations_code(fields))}

        _error ->
          {:ok, relations_zipper}
      end
    end

    defp villain_relations_code(fields) do
      Enum.map_join(fields, "\n", fn field ->
        "relation #{inspect(field)}, :has_many, module: :blocks"
      end)
    end

    defp remove_villain_attributes(zipper) do
      {:ok, Common.remove_all_matches(zipper, &villain_attribute?(&1))}
    end

    defp collect_villain_fields(zipper) do
      zipper
      |> Common.find_all(&villain_attribute?(&1))
      |> Enum.map(fn attribute_zipper ->
        attribute_zipper
        |> Zipper.node()
        |> Sourceror.get_args()
        |> List.first()
        |> literal_atom!()
        |> villain_relation_name()
      end)
      |> Enum.uniq()
    end

    defp villain_relation_name(:data), do: :blocks

    defp villain_relation_name(name) do
      name = Atom.to_string(name)

      if String.ends_with?(name, "_data") do
        name
        |> String.trim_trailing("_data")
        |> Kernel.<>("_blocks")
        |> String.to_atom()
      else
        String.to_atom("#{name}_blocks")
      end
    end

    defp relation_declared?(zipper, field) do
      zipper
      |> Common.find_all(fn relation_zipper ->
        CodeFunction.function_call?(relation_zipper, :relation) and
          CodeFunction.argument_equals?(relation_zipper, 0, field)
      end)
      |> Enum.any?()
    end

    defp rewrite_meta_field(zipper) do
      Common.update_all_matches(zipper, &meta_field?(&1), fn zipper ->
        case zipper |> Zipper.node() |> Sourceror.get_args() do
          [targets, path, mutator] ->
            {:ok, replace_path_field(zipper, targets, nil, path, mutator)}

          [targets, path_or_function] ->
            {:ok, replace_path_or_rename(zipper, targets, nil, path_or_function)}
        end
      end)
    end

    defp replace_path_or_rename(zipper, name, type, path_or_function) do
      if literal_list?(path_or_function) do
        replace_path_field(zipper, name, type, path_or_function)
      else
        rename_call(zipper, :field)
      end
    end

    defp rewrite_json_ld_field(zipper) do
      Common.update_all_matches(zipper, &json_ld_field?(&1), fn zipper ->
        case zipper |> Zipper.node() |> Sourceror.get_args() do
          [name, reference] ->
            {:ok, rewrite_json_ld_reference(zipper, name, reference)}

          [name, type, path, mutator] ->
            {:ok, replace_path_field(zipper, name, type, path, mutator)}

          [name, type, path_or_function] ->
            {:ok, replace_path_or_rename(zipper, name, type, path_or_function)}
        end
      end)
    end

    defp rewrite_json_ld_reference(zipper, name, reference) do
      case reference_target(reference) do
        {:ok, target} ->
          Common.replace_code(zipper, json_ld_reference_field(name, target))

        :error ->
          rename_call(zipper, :field)
      end
    end

    defp json_ld_reference_field(name, target) do
      if literal_atom_value(target) == :identity do
        quote do
          field unquote(name), :identity
        end
      else
        quote do
          field unquote(name), :string, fn _entry ->
            %{"@id" => "#{Brando.Utils.hostname()}/##{unquote(target)}"}
          end
        end
      end
    end

    defp replace_path_field(zipper, name, type, path, mutator \\ nil) do
      access_path = path |> literal_list_value() |> Enum.map(&access_key_ast/1)

      value_function =
        if is_nil(mutator) do
          quote do
            fn entry -> get_in(entry, unquote(access_path)) end
          end
        else
          value = quote(do: get_in(entry, unquote(access_path)))

          quote do
            fn entry -> unquote(capture_call(mutator, [value])) end
          end
        end

      replacement =
        if is_nil(type) do
          quote do
            field unquote(name), unquote(value_function)
          end
        else
          quote do
            field unquote(name), unquote(type), unquote(value_function)
          end
        end

      Common.replace_code(zipper, replacement)
    end

    defp access_key_ast(key) do
      quote do
        Access.key(unquote(key))
      end
    end

    # `&encode_locale/1` applied to `args` reads `encode_locale(value)`, and
    # `&Mod.fun/2` `Mod.fun(a, b)`; any other function value is called with `.()`.
    defp capture_call({:&, _, [{:/, _, [function, arity]}]} = capture, args) do
      case {function, literal_integer(arity) == length(args)} do
        {{name, _, context}, true} when is_atom(name) and is_atom(context) ->
          {name, [], args}

        {{{:., _, [module, name]}, _, []}, true} when is_atom(name) ->
          {{:., [], [module, name]}, [], args}

        _other ->
          quote(do: unquote(capture).(unquote_splicing(args)))
      end
    end

    defp capture_call(function, args), do: quote(do: unquote(function).(unquote_splicing(args)))

    defp literal_integer({:__block__, _, [value]}), do: value
    defp literal_integer(value), do: value

    defp rename_call(zipper, new_name) do
      case Zipper.node(zipper) do
        {_old_name, metadata, arguments} -> Zipper.replace(zipper, {new_name, metadata, arguments})
        _other -> zipper
      end
    end

    defp rewrite_listing_query(zipper) do
      Common.update_all_matches(
        zipper,
        &listing_query?(&1),
        fn zipper ->
          zipper =
            case Zipper.node(zipper) do
              {:listing_query, metadata, arguments} ->
                new_node = {:query, metadata, arguments}
                Zipper.replace(zipper, new_node)

              _ ->
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp rewrite_form_query(zipper) do
      Common.update_all_matches(
        zipper,
        &form_query?(&1),
        fn zipper ->
          zipper =
            case Zipper.node(zipper) do
              {:form_query, metadata, arguments} ->
                new_node = {:query, metadata, arguments}
                Zipper.replace(zipper, new_node)

              _ ->
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp rewrite_slug_source(zipper), do: rewrite_input_for_option(zipper, &input_slug?/1, :source)

    defp rewrite_entries_sources(zipper) do
      rewrite_input_for_option(zipper, &input_entries?/1, :sources)
    end

    defp rewrite_input_for_option(zipper, predicate, replacement_key) do
      Common.update_all_matches(zipper, predicate, fn zipper ->
        case CodeFunction.move_to_nth_argument(zipper, 2) do
          {:ok, options_zipper} ->
            options =
              options_zipper
              |> Zipper.node()
              |> Enum.map(&rename_for_option(&1, replacement_key))

            {:ok, options_zipper |> Zipper.replace(options) |> Zipper.up()}

          :error ->
            {:ok, zipper}
        end
      end)
    end

    defp rename_for_option({{:__block__, metadata, [old_key]}, value}, replacement_key)
         when old_key in [:for, :from] do
      {{:__block__, metadata, [replacement_key]}, value}
    end

    defp rename_for_option(
           {{:__block__, metadata, [old_key]}, value_metadata, value},
           replacement_key
         )
         when old_key in [:for, :from] do
      {{:__block__, metadata, [replacement_key]}, value_metadata, value}
    end

    defp rename_for_option(other, _replacement_key), do: other

    defp rewrite_inputs_for(zipper) do
      Common.update_all_matches(
        zipper,
        &inputs_for_with_three_arity?(&1),
        fn zipper ->
          with {:ok, zipper} <- CodeFunction.move_to_nth_argument(zipper, 1),
               macros <- extract_macros(zipper),
               zipper <- Zipper.remove(zipper),
               {:ok, zipper} <- Common.move_to_do_block(zipper),
               zipper <- Common.add_code(zipper, macros, placement: :before) do
            fs =
              zipper
              |> Zipper.up()
              |> Zipper.up()
              |> Zipper.up()

            {:ok, fs}
          else
            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp rewrite_fieldsets(zipper) do
      Common.update_all_matches(
        zipper,
        &fieldset_with_two_arity?(&1),
        fn zipper ->
          with {:ok, zipper} <- CodeFunction.move_to_nth_argument(zipper, 0),
               macros <- extract_macros(zipper),
               zipper <- Zipper.remove(zipper),
               {:ok, zipper} <- Common.move_to_do_block(zipper),
               zipper <- Common.add_code(zipper, macros, placement: :before) do
            fs =
              zipper
              |> Zipper.up()
              |> Zipper.up()
              |> Zipper.up()

            {:ok, fs}
          else
            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp rewrite_traits(zipper) do
      Common.update_all_matches(
        zipper,
        &trait_villain?(&1),
        fn zipper ->
          new_trait = "trait Brando.Trait.Blocks"
          {:ok, Common.replace_code(zipper, new_trait)}
        end
      )
    end

    defp rewrite_forms(zipper) do
      Common.update_all_matches(
        zipper,
        &forms_with_keyword_lists?(&1),
        fn zipper ->
          option_index =
            if CodeFunction.function_call?(zipper, :form, 3),
              do: 1,
              else: 0

          case CodeFunction.move_to_nth_argument(zipper, option_index) do
            {:ok, zipper} ->
              macros = extract_macros(zipper)
              zipper = Zipper.remove(zipper)
              {:ok, zipper} = Common.move_to_do_block(zipper)
              zipper = Common.add_code(zipper, macros, placement: :before)

              fs =
                zipper
                |> Zipper.up()
                |> Zipper.up()
                |> Zipper.up()

              {:ok, fs}

            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp extract_macros(zipper), do: zipper |> Zipper.node() |> extract_macros_from_ast()

    defp extract_macros_from_ast(ast) do
      ast
      |> keyword_entries()
      |> Enum.map_join("\n", fn
        {{:__block__, _, [key]}, {:__block__, _, [value]}}
        when is_atom(key) and is_atom(value) ->
          "#{key} #{inspect(value)}"

        {{:__block__, _, [key]}, value} when is_atom(key) ->
          "#{key} #{Sourceror.to_string(value)}"

        {key, value} when is_atom(key) ->
          "#{key} #{Sourceror.to_string(value)}"
      end)
    end

    defp keyword_entries({:__block__, _, [entries]}) when is_list(entries), do: entries
    defp keyword_entries(entries) when is_list(entries), do: entries

    @doc "Finds every module that `use Brando.Blueprint`: `{igniter, modules}`."
    def find_blueprints(igniter) do
      ProjectModule.find_all_matching_modules(igniter, fn _module, zipper ->
        case Igniter.Code.Module.move_to_use(zipper, Brando.Blueprint) do
          {:ok, _zipper} -> true
          _ -> false
        end
      end)
    end

    defp fieldset_with_two_arity?(zipper) do
      CodeFunction.function_call?(zipper, :fieldset, 2)
    end

    defp inputs_for_with_three_arity?(zipper) do
      CodeFunction.function_call?(zipper, :inputs_for, 3)
    end

    defp forms_with_keyword_lists?(zipper) do
      (CodeFunction.function_call?(zipper, :form, 2) and
         CodeFunction.argument_matches_predicate?(zipper, 0, fn argument_zipper ->
           Igniter.Code.List.list?(argument_zipper)
         end)) or
        (CodeFunction.function_call?(zipper, :form, 3) and
           CodeFunction.argument_matches_predicate?(zipper, 1, fn argument_zipper ->
             Igniter.Code.List.list?(argument_zipper)
           end))
    end

    defp input_entries?(zipper) do
      CodeFunction.function_call?(zipper, :input, 3) &&
        CodeFunction.argument_equals?(zipper, 1, :entries) &&
        CodeFunction.argument_matches_predicate?(zipper, 2, fn argument_zipper ->
          Igniter.Code.Keyword.keyword_has_path?(argument_zipper, [:for])
        end)
    end

    defp listing_filter_with_legacy_key?(zipper) do
      CodeFunction.function_call?(zipper, :filter, 1) and
        CodeFunction.argument_matches_predicate?(zipper, 0, fn argument_zipper ->
          Igniter.Code.Keyword.keyword_has_path?(argument_zipper, [:filter])
        end)
    end

    defp json_ld_field?(zipper) do
      CodeFunction.function_call?(zipper, :json_ld_field, 2) ||
        CodeFunction.function_call?(zipper, :json_ld_field, 3) ||
        CodeFunction.function_call?(zipper, :json_ld_field, 4)
    end

    defp listing_query?(zipper) do
      CodeFunction.function_call?(zipper, :listing_query, 1)
    end

    defp form_query?(zipper) do
      CodeFunction.function_call?(zipper, :form_query, 1)
    end

    defp meta_field?(zipper) do
      CodeFunction.function_call?(zipper, :meta_field, 2) ||
        CodeFunction.function_call?(zipper, :meta_field, 3)
    end

    defp input_slug?(zipper) do
      CodeFunction.function_call?(zipper, :input, 3) &&
        CodeFunction.argument_equals?(zipper, 1, :slug) &&
        CodeFunction.argument_matches_predicate?(zipper, 2, fn argument_zipper ->
          Igniter.Code.Keyword.keyword_has_path?(argument_zipper, [:for]) ||
            Igniter.Code.Keyword.keyword_has_path?(argument_zipper, [:from])
        end)
    end

    defp villain_attribute?(zipper) do
      CodeFunction.function_call?(zipper, :attribute, 2) &&
        CodeFunction.argument_equals?(zipper, 1, :villain)
    end

    defp trait_villain?(zipper) do
      CodeFunction.function_call?(zipper, :trait) &&
        CodeFunction.argument_equals?(zipper, 0, Brando.Trait.Villain)
    end

    defp use_datasource?(zipper) do
      CodeFunction.function_call?(zipper, :use) &&
        CodeFunction.argument_equals?(zipper, 0, Brando.Datasource)
    end

    defp uses_legacy_datasource?(zipper) do
      zipper
      |> Common.find_all(&use_datasource?(&1))
      |> Enum.any?()
    end

    defp list_datasource?(zipper) do
      CodeFunction.function_call?(zipper, :list, 2) and
        datasource_arguments?(zipper, 2)
    end

    defp single_datasource?(zipper) do
      CodeFunction.function_call?(zipper, :single, 2) and
        datasource_arguments?(zipper, 2)
    end

    defp selection_datasource?(zipper) do
      CodeFunction.function_call?(zipper, :selection, 3) and
        datasource_arguments?(zipper, 3)
    end

    defp datasource_arguments?(zipper, arity) do
      arguments = zipper |> Zipper.node() |> Sourceror.get_args()

      case {arity, arguments} do
        {2, [key, callback]} ->
          literal_atom?(key) and callback_ast?(callback)

        {3, [key, list_callback, get_callback]} ->
          literal_atom?(key) and callback_ast?(list_callback) and callback_ast?(get_callback)

        _other ->
          false
      end
    end

    defp literal_atom?({:__block__, _, [value]}), do: is_atom(value)
    defp literal_atom?(value), do: is_atom(value)

    defp literal_atom!({:__block__, _, [value]}) when is_atom(value), do: value
    defp literal_atom!(value) when is_atom(value), do: value

    defp literal_atom_value({:__block__, _, [value]}) when is_atom(value), do: value
    defp literal_atom_value(value) when is_atom(value), do: value
    defp literal_atom_value(_value), do: nil

    defp callback_ast?({:fn, _, _}), do: true
    defp callback_ast?({:&, _, _}), do: true

    defp callback_ast?({:{}, _, [_module, function, args]}) do
      literal_atom?(function) and literal_list?(args)
    end

    defp callback_ast?(_), do: false

    defp literal_list?({:__block__, _, [value]}), do: is_list(value)
    defp literal_list?(value), do: is_list(value)

    defp literal_list_value({:__block__, _, [value]}) when is_list(value), do: value
    defp literal_list_value(value) when is_list(value), do: value

    defp reference_target({:__block__, _, [{key, target}]}) do
      if literal_atom_value(key) == :references, do: {:ok, target}, else: :error
    end

    defp reference_target({key, target}) do
      if literal_atom_value(key) == :references, do: {:ok, target}, else: :error
    end

    defp reference_target(_reference), do: :error

    defp legacy_listing_export?(zipper) do
      if CodeFunction.function_call?(zipper, :export, 2) do
        case zipper |> Zipper.node() |> Sourceror.get_args() do
          [name, options] ->
            keys = keyword_keys(options)

            literal_atom?(name) and :label in keys and :fields in keys and
              Enum.all?(keys, &(&1 in [:label, :type, :query, :fields, :description]))

          _other ->
            false
        end
      else
        false
      end
    end

    defp legacy_actions_with_options?(zipper) do
      if CodeFunction.function_call?(zipper, :actions, 2) do
        case zipper |> Zipper.node() |> Sourceror.get_args() do
          [items, options] ->
            literal_list?(items) and keyword_keys(options) == [:default_actions]

          _other ->
            false
        end
      else
        false
      end
    end

    defp keyword_keys(options) do
      options
      |> keyword_entries()
      |> Enum.map(fn
        {{:__block__, _, [key]}, _value} when is_atom(key) -> key
        {key, _value} when is_atom(key) -> key
        _other -> nil
      end)
      |> Enum.reject(&is_nil/1)
    rescue
      FunctionClauseError -> []
    end

    ## Templates

    @template_extensions ~w(.ex .heex .eex .leex)
    @template_finding_limit 50
    # Brando's own schemas whose templates read a Villain `html` until 0.54.
    @brando_block_templates [{"page", [{"html", "rendered_blocks"}]}]

    @doc """
    Points templates at the fields 0.54 renders blocks into, and lists the
    template code 0.54 breaks that it cannot rewrite.

    A Villain field's HTML (`html` for `data`, `hero_html` for `hero_data`)
    became `rendered_<relation>` (`rendered_blocks`, `rendered_hero_blocks`).
    Reads of it on `entry`/`@entry` or the schema's singular are rewritten in
    the schema's own templates: a `<singular>_html` directory or module,
    `templates/<singular>`, or `<singular>_view.ex`, and there only in
    Elixir code (`Mix.Brando.Igniter.TemplateCode`), never in a script or in
    text. Pages count as the `page` schema. Run it before the Blueprint rewrite, which removes the
    Villain attributes; a Blueprint an earlier run already moved is matched
    by its block relations.

    Navigation item reads (`item.url`, `item.title`, `item.open_in_new_window`,
    `item.items`) become `Brando.HTML.get_menu_item_url(item)` and the other
    link helpers, and `item.children`, for a variable bound by a generator
    over a navigation's or menu's `items` (`Mix.Brando.Igniter.SourceUpgrade.NavigationItems`).

    When a template reads `@page`'s vars, `:vars` is added to the `preload`
    of each `Pages.get_page/1` call written with a map
    (`Mix.Brando.Igniter.SourceUpgrade.PageVars`).

    It warns, with file and line, about the reads it left, and page var
    reads it cannot tell are loaded with `preload: [:vars]`.
    """
    def upgrade_054_templates(igniter) do
      {igniter, blueprints} = find_blueprints(igniter)

      {igniter, fields} =
        Enum.reduce(blueprints, {igniter, []}, fn module, {igniter, fields} ->
          {:ok, {igniter, _source, zipper}} = ProjectModule.find_module(igniter, module)
          {igniter, fields ++ blueprint_html_fields(zipper)}
        end)

      {by_singular, ambiguous} = template_renames(fields)
      igniter = Igniter.include_glob(igniter, "lib/**/*.{ex,heex,eex,leex}")

      igniter =
        igniter
        |> template_paths()
        |> Enum.reduce(igniter, fn path, igniter ->
          case template_singular(path, Map.keys(by_singular)) do
            nil -> igniter
            singular -> rewrite_html_reads(igniter, path, singular, by_singular[singular])
          end
        end)

      html_fields = for {_singular, renames} <- fields, {html, _rendered} <- renames, uniq: true, do: html

      igniter
      |> NavigationItems.rewrite(template_paths(igniter))
      |> warn_054_template_reads(html_fields, ambiguous)
    end

    # `{singular, [{html_field, rendered_field}]}` for one Blueprint.
    defp blueprint_html_fields(zipper) do
      case blueprint_naming(zipper) do
        %{singular: singular} -> [{singular, html_renames(zipper)}]
        _naming -> []
      end
    end

    # The literal `domain`, `schema` and `singular` options of a Blueprint's
    # `use Brando.Blueprint`, given its `defmodule` zipper.
    defp blueprint_naming(zipper) do
      with {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, use_zipper} <- Igniter.Code.Module.move_to_use(body, Brando.Blueprint),
           {:ok, options} <- CodeFunction.move_to_nth_argument(use_zipper, 1) do
        for key <- [:domain, :schema, :singular],
            {:ok, value} <- [Igniter.Code.Keyword.get_key(options, key)],
            {:__block__, _, [string]} when is_binary(string) <- [Zipper.node(value)],
            into: %{},
            do: {key, string}
      else
        _ -> %{}
      end
    end

    defp html_renames(zipper) do
      attributes = declared_attribute_names(zipper)

      villain =
        zipper
        |> Common.find_all(&villain_attribute?/1)
        |> Enum.map(&(&1 |> Zipper.node() |> Sourceror.get_args() |> List.first() |> literal_atom!()))
        |> Enum.filter(&String.contains?(Atom.to_string(&1), "data"))
        |> Enum.map(&{String.replace(Atom.to_string(&1), "data", "html"), villain_relation_name(&1)})

      relations =
        for relation <- block_relation_names(zipper),
            html = relation_html_field(relation),
            not is_nil(html),
            do: {html, relation}

      (villain ++ relations)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.reject(fn {html, _relation} -> html in attributes end)
      |> Enum.map(fn {html, relation} -> {html, "rendered_#{relation}"} end)
      |> Enum.sort()
    end

    defp relation_html_field(:blocks), do: "html"

    defp relation_html_field(relation) do
      name = Atom.to_string(relation)
      if String.ends_with?(name, "_blocks"), do: String.replace_suffix(name, "_blocks", "_html")
    end

    defp declared_attribute_names(zipper) do
      zipper
      |> Common.find_all(&CodeFunction.function_call?(&1, :attribute, [2, 3]))
      |> Enum.flat_map(fn attribute ->
        case single_child(attribute) do
          {:attribute, _, [name | _]} -> [to_string(literal_atom_value(name))]
          _ -> []
        end
      end)
    end

    defp block_relation_names(zipper) do
      zipper
      |> Common.find_all(&CodeFunction.function_call?(&1, :relation, 3))
      |> Enum.flat_map(fn relation ->
        with {:relation, _, [name, type, options]} <- single_child(relation),
             :has_many <- literal_atom_value(type),
             true <- block_module_option?(options),
             name when is_atom(name) and not is_nil(name) <- literal_atom_value(name) do
          [name]
        else
          _ -> []
        end
      end)
    end

    defp block_module_option?(options) do
      Enum.any?(keyword_entries(options), fn
        {key, value} -> literal_atom_value(key) == :module and literal_atom_value(value) == :blocks
        _other -> false
      end)
    rescue
      FunctionClauseError -> false
    end

    # Schemas sharing a singular share their template directories, so they
    # are rewritten only when their fields agree.
    defp template_renames(fields) do
      (fields ++ @brando_block_templates)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.reduce({%{}, []}, fn {singular, renames}, {by_singular, ambiguous} ->
        case Enum.uniq(renames) do
          [[]] -> {by_singular, ambiguous}
          [renames] -> {Map.put(by_singular, singular, renames), ambiguous}
          _differing -> {by_singular, [singular | ambiguous]}
        end
      end)
    end

    defp template_paths(igniter) do
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.filter(&(String.starts_with?(&1, "lib/") and Path.extname(&1) in @template_extensions))
      |> Enum.sort()
    end

    defp template_singular(path, singulars) do
      {directories, [basename]} = path |> Path.split() |> Enum.split(-1)
      pairs = Enum.chunk_every(directories, 2, 1, :discard)

      Enum.find(singulars, fn singular ->
        "#{singular}_html" in directories or ["templates", singular] in pairs or
          basename in ["#{singular}_html.ex", "#{singular}_view.ex"]
      end)
    end

    defp rewrite_html_reads(igniter, path, singular, renames) do
      content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)
      fields = Enum.map_join(renames, "|", &Regex.escape(elem(&1, 0)))
      regex = ~r/(?<![\w.:"'\/@])(@?(?:entry|#{Regex.escape(singular)}))\.(#{fields})(?![\w.(])/
      renames = Map.new(renames)
      # Only Elixir code: the same text in a script or in prose is not a field read.
      code? = TemplateCode.code?(content, path)

      updated =
        regex
        |> Regex.scan(content, return: :index)
        |> Enum.filter(fn [{start, _length} | _groups] -> code?.(start) end)
        |> Enum.reverse()
        |> Enum.reduce(content, fn [_read, _variable, {start, length}], content ->
          field = binary_part(content, start, length)

          binary_part(content, 0, start) <>
            renames[field] <> binary_part(content, start + length, byte_size(content) - start - length)
        end)

      if updated == content,
        do: igniter,
        else: Igniter.update_file(igniter, path, &Source.update(&1, :content, updated))
    end

    defp warn_054_template_reads(igniter, html_fields, ambiguous) do
      fields = Enum.map_join(Enum.uniq(["html" | html_fields]), "|", &Regex.escape/1)
      html_read = ~r/(?<![\w.:"'\/@])@?[a-z_]\w*(?:\.[a-z_]\w*)*\.(?:#{fields})(?![\w.(])/

      sources =
        igniter
        |> template_paths()
        |> Enum.map(&{&1, igniter.rewrite |> Rewrite.source!(&1) |> Source.get(:content)})

      {igniter, page_vars} = PageVars.preload(igniter, sources)

      [
        {"""
         Villain HTML reads. 0.54 renders blocks into `rendered_<relation>`:
         `entry.html` is now `entry.rendered_blocks`, `entry.hero_html` is
         `entry.rendered_hero_blocks`. These lines were left as they are: they
         are outside a schema's own templates#{ambiguous_note(ambiguous)}, or not
         Elixir code (a script, CSS or text):
         """, findings(sources, fn _content -> &Regex.match?(html_read, &1) end)},
        {"""
         Navigation items. An item no longer has `url`, `title`,
         `open_in_new_window` or `items`; it holds a link var. The task rewrote
         these reads where the file binds the item name only to navigation
         items; use `Brando.HTML.get_menu_item_url(item)`,
         `get_menu_item_text(item)`, `get_menu_item_target_blank(item)` and
         `item.children` in these lines:
         """, findings(sources, &NavigationItems.read?/1)}
      ]
      |> Kernel.++(page_vars)
      |> Enum.reject(fn {_text, findings} -> findings == [] end)
      |> case do
        [] ->
          igniter

        sections ->
          Igniter.add_warning(igniter, """
          Template code that 0.54 breaks and the task did not rewrite (matched
          by name, so check each line):

          #{Enum.map_join(sections, "\n", fn {text, findings} -> text <> format_findings(findings) end)}
          """)
      end
    end

    defp ambiguous_note([]), do: ""

    defp ambiguous_note(singulars) do
      ", or in templates of schemas that share a singular (#{singulars |> Enum.sort() |> Enum.join(", ")})"
    end

    # `line_predicate` takes a file's content and returns the test for its lines.
    defp findings(sources, line_predicate) do
      for {path, content} <- sources,
          matches? = line_predicate.(content),
          {line, number} <- content |> String.split("\n") |> Enum.with_index(1),
          matches?.(line),
          do: "#{path}:#{number}: #{String.trim(line)}"
    end

    defp format_findings(findings) do
      shown = Enum.take(findings, @template_finding_limit)
      more = length(findings) - length(shown)
      Enum.map_join(shown, "\n", &("  " <> &1)) <> if(more > 0, do: "\n  … and #{more} more\n", else: "\n")
    end

    def rename_list_villains(igniter) do
      Rename.rename_function(
        igniter,
        {Brando.Villain, :list_villains},
        {Brando.Villain, :list_blocks},
        arity: 0
      )
    end

    @doc "See `Mix.Brando.Igniter.ModuleRenames.rewrite/1`."
    defdelegate rename_moved_modules(igniter), to: Mix.Brando.Igniter.ModuleRenames, as: :rewrite

    def configure_repo_module(igniter) do
      case Igniter.Libs.Ecto.list_repos(igniter) do
        {igniter, [repo]} ->
          Config.configure_new(igniter, "brando.exs", :brando, [:repo_module], repo)

        {igniter, []} ->
          Igniter.add_warning(igniter, "Could not infer `config :brando, repo_module:` because no Ecto Repo was found.")

        {igniter, repos} ->
          Igniter.add_warning(
            igniter,
            "Could not infer `config :brando, repo_module:` because multiple Ecto Repos were found: #{inspect(repos)}"
          )
      end
    end

    @doc """
    Removes `processor_module: Brando.Images.Processor.Sharp` from
    `config :brando, Brando.Images` in `config/*.exs`. The Sharp processor is
    gone and Brando refuses to boot with it; the default is
    `Brando.Images.Processor.Vix`. Other processors are left alone.
    """
    def remove_sharp_processor(igniter) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")

      # Only files that name the processor are touched: updating a file
      # reformats it.
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.filter(
        &(Path.dirname(&1.path) == "config" and Path.extname(&1.path) == ".exs" and
            Source.get(&1, :content) =~ "Brando.Images.Processor.Sharp")
      )
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.reduce(igniter, fn path, igniter ->
        Igniter.update_elixir_file(igniter, path, fn zipper ->
          Common.update_all_matches(zipper, &sharp_processor_config?/1, &drop_processor_module/1)
        end)
      end)
    end

    defp sharp_processor_config?(zipper) do
      with true <- CodeFunction.function_call?(zipper, :config, 3),
           true <- CodeFunction.argument_equals?(zipper, 0, :brando),
           true <- CodeFunction.argument_equals?(zipper, 1, Brando.Images),
           {:ok, options} <- CodeFunction.move_to_nth_argument(zipper, 2),
           {:ok, processor} <- Igniter.Code.Keyword.get_key(options, :processor_module) do
        Common.nodes_equal?(processor, Brando.Images.Processor.Sharp)
      else
        _ -> false
      end
    end

    defp drop_processor_module(zipper) do
      with {:ok, options} <- CodeFunction.move_to_nth_argument(zipper, 2),
           {:ok, options} <- Igniter.Code.Keyword.remove_keyword_key(options, :processor_module) do
        case Zipper.node(options) do
          # It was the only option: the whole call goes.
          {:__block__, _, [[]]} -> {:ok, options |> Zipper.up() |> Zipper.remove()}
          [] -> {:ok, options |> Zipper.up() |> Zipper.remove()}
          _ -> {:ok, Zipper.up(options)}
        end
      else
        _ -> {:ok, zipper}
      end
    end

    # What the 0.53 `use Brando.Villain.Parser` brought into the module, beyond
    # the callbacks. `use Phoenix.Component` and the imports are added when the
    # parser uses them; an alias when the parser names it without its own.
    @parser_imports [Brando.HTML, Phoenix.HTML]
    @parser_aliases [Brando.Cache, Brando.Content, Brando.Datasource, Brando.Utils, Brando.Villain, Liquex.Context]

    @doc """
    Updates application modules that `use Brando.Villain.Parser`.

    The parser's `__using__` used to `use Phoenix.Component`, import
    `Brando.HTML` and `Phoenix.HTML`, and alias `Brando.Cache`, `Content`,
    `Datasource`, `Utils`, `Villain` and `Liquex.Context`; it no longer does.
    A parser gets back the ones it uses: `use Phoenix.Component` when it
    renders `~H`, an import when it calls one of the module's functions (or
    renders one of `Brando.HTML`'s components, such as `<.picture>`), and an
    alias when it names one without defining that alias itself. Nothing it
    does not use is added, so no unused import warnings.

    Public overrides of a block Brando no longer has (for example
    `slideshow/2`, which became `gallery` in `brando_77`) are never called;
    each is reported.
    """
    def update_villain_parsers(igniter) do
      {igniter, parsers} =
        ProjectModule.find_all_matching_modules(igniter, fn _module, zipper ->
          match?({:ok, _}, Igniter.Code.Module.move_to_use(zipper, Brando.Villain.Parser))
        end)

      Enum.reduce(parsers, igniter, &update_villain_parser(&2, &1))
    end

    defp update_villain_parser(igniter, parser) do
      {:ok, {igniter, _source, defmodule}} = ProjectModule.find_module(igniter, parser)
      {:ok, zipper} = Common.move_to_do_block(defmodule)
      igniter = warn_dead_parser_overrides(igniter, parser, zipper)

      case missing_parser_code(zipper) do
        [] -> igniter
        lines -> ProjectModule.find_and_update_module!(igniter, parser, &add_after_parser_use(&1, lines))
      end
    end

    defp missing_parser_code(zipper) do
      ast = Zipper.node(zipper)
      calls = parser_calls(ast)
      defined = defined_functions(ast, [:def, :defp, :defmacro, :defmacrop])

      component =
        if renders_heex?(zipper) and not uses_or_imports?(zipper, Phoenix.Component),
          do: ["use Phoenix.Component"],
          else: []

      imports =
        for module <- @parser_imports,
            not uses_or_imports?(zipper, module),
            calls_function_of?(calls, defined, module),
            do: "import #{inspect(module)}"

      aliases =
        for module <- @parser_aliases,
            short = module |> Module.split() |> List.last() |> String.to_atom(),
            names_alias?(ast, short),
            not defines_alias?(ast, short),
            do: "alias #{inspect(module)}"

      component ++ imports ++ aliases
    end

    defp add_after_parser_use(zipper, lines) do
      with {:ok, zipper} <- Igniter.Code.Module.move_to_use(zipper, Brando.Villain.Parser) do
        {:ok, Common.add_code(zipper, Enum.join(lines, "\n"), placement: :after)}
      end
    end

    defp renders_heex?(zipper), do: Zipper.find(zipper, &match?({:sigil_H, _, _}, &1)) != nil

    defp uses_or_imports?(zipper, module) do
      match?({:ok, _}, Igniter.Code.Module.move_to_use(zipper, module)) or
        match?(
          {:ok, _},
          Common.move_to(zipper, fn zipper ->
            CodeFunction.function_call?(zipper, :import) and CodeFunction.argument_equals?(zipper, 0, module)
          end)
        )
    end

    # Unqualified calls as `{name, arity}`, and calls inside `~H` templates
    # (components and `{expressions}`) as `{name, :any}`.
    defp parser_calls(ast) do
      {_ast, calls} =
        Macro.prewalk(ast, [], fn
          {:|>, _, [_left, {name, _, args}]} = node, acc when is_atom(name) and is_list(args) ->
            {node, [{name, length(args) + 1} | acc]}

          {:&, _, [{:/, _, [{name, _, context}, arity]}]} = node, acc when is_atom(name) and is_atom(context) ->
            {node, [{name, unwrap_literal(arity)} | acc]}

          {:sigil_H, _, [{:<<>>, _, parts} | _]} = node, acc ->
            template = parts |> Enum.filter(&is_binary/1) |> Enum.join()
            {node, heex_calls(template) ++ acc}

          {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
            {node, [{name, length(args)} | acc]}

          node, acc ->
            {node, acc}
        end)

      Enum.uniq(calls)
    end

    defp heex_calls(template) do
      components = for [_, name] <- Regex.scan(~r/<\.([a-z_]\w*[?!]?)/, template), do: {String.to_atom(name), 1}

      expressions =
        for [_, name] <- Regex.scan(~r/(?<![\w.])([a-z_]\w*[?!]?)\(/, template), do: {String.to_atom(name), :any}

      components ++ expressions
    end

    defp unwrap_literal({:__block__, _, [value]}), do: value
    defp unwrap_literal(value), do: value

    defp calls_function_of?(calls, defined, module) do
      exports = if Code.ensure_loaded?(module), do: module.__info__(:functions), else: []
      export_names = MapSet.new(exports, &elem(&1, 0))
      defined_names = MapSet.new(defined, &elem(&1, 0))

      Enum.any?(calls, fn
        {name, :any} -> name in export_names and name not in defined_names
        call -> call in exports and call not in defined
      end)
    end

    defp names_alias?(ast, short) do
      ast
      |> Macro.prewalk(false, fn
        {:__aliases__, _, [^short | _]} = node, _found -> {node, true}
        node, found -> {node, found}
      end)
      |> elem(1)
    end

    # `alias Foo.Short`, `alias Foo.{Short, ...}` or `alias Foo, as: Short`
    defp defines_alias?(ast, short) do
      ast
      |> Macro.prewalk(false, fn
        {:alias, _, [_target, opts]} = node, found when is_list(opts) ->
          {node, found or alias_as?(opts, short)}

        {:alias, _, [{{:., _, [_base, :{}]}, _, children}]} = node, found ->
          {node, found or Enum.any?(children, &match?({:__aliases__, _, [^short]}, &1))}

        {:alias, _, [{:__aliases__, _, parts}]} = node, found ->
          {node, found or Enum.join(parts, ".") =~ ~r/(^|\.)#{short}$/}

        node, found ->
          {node, found}
      end)
      |> elem(1)
    end

    defp alias_as?(opts, short) do
      Enum.any?(opts, fn
        {{:__block__, _, [:as]}, {:__aliases__, _, [^short]}} -> true
        {:as, {:__aliases__, _, [^short]}} -> true
        _option -> false
      end)
    end

    defp warn_dead_parser_overrides(igniter, parser, zipper) do
      callbacks = Brando.Villain.Parser.overridable_callbacks()

      zipper
      |> Zipper.node()
      |> defined_functions([:def])
      |> Enum.reject(&(&1 in callbacks))
      |> Enum.filter(fn {_name, arity} -> arity == 2 end)
      |> Enum.reduce(igniter, fn {name, arity}, igniter ->
        Igniter.add_warning(igniter, """
        #{inspect(parser)}.#{name}/#{arity} overrides no block Brando renders, so it is never called.
        Delete it, or move its markup to a module or to the `gallery`/`media` override that replaced it.
        """)
      end)
    end

    defp defined_functions(ast, kinds) do
      {_ast, functions} =
        Macro.prewalk(ast, [], fn
          {kind, _, [{:when, _, [head | _]} | _]} = node, acc ->
            if kind in kinds, do: {node, [function_head(head) | acc]}, else: {node, acc}

          {kind, _, [head | _]} = node, acc when is_atom(kind) ->
            if kind in kinds, do: {node, [function_head(head) | acc]}, else: {node, acc}

          node, acc ->
            {node, acc}
        end)

      functions |> Enum.reject(&is_nil/1) |> Enum.uniq()
    end

    defp function_head({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
    defp function_head(_head), do: nil

    # 0.53 Blueprints translated into one domain per context.
    @context_catalog ~r/\A(?<domain>.+)_(?<context>naming|forms|listings)\.po\z/
    @context_order %{"naming" => 0, "forms" => 1, "listings" => 2}

    @doc """
    Copies the translations of 0.53's per-context Blueprint domains into the
    domain 0.55 uses, in every `priv/gettext/**/LC_MESSAGES` directory.

    0.53 translated a Blueprint's strings into `<domain>_<schema>_naming`,
    `_forms` and `_listings`; 0.55 into `<domain>_<schema>`. Extracting
    writes the new domain with empty translations and empties the old ones,
    so the translated messages are copied into `<domain>_<schema>.po` first,
    where the merge keeps them. Only domains of the application's Blueprints
    are read; a message already translated in the target is kept. When the
    contexts translate a message differently, `naming` wins over `forms`
    over `listings`, and the others are reported.
    """
    def carry_blueprint_translations(igniter) do
      {igniter, blueprints} = find_blueprints(igniter)

      # Each Blueprint domain, and the catalog directories of the Gettext
      # backends that translate it: a copy elsewhere is read by nothing.
      domains =
        blueprints
        |> Enum.flat_map(fn module ->
          {:ok, {_igniter, _source, zipper}} = ProjectModule.find_module(igniter, module)

          case blueprint_naming(zipper) do
            %{domain: domain, schema: schema} ->
              [{String.downcase("#{domain}_#{schema}"), BlueprintCatalogs.priv(igniter, zipper)}]

            _naming ->
              []
          end
        end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      igniter = Igniter.include_glob(igniter, "priv/gettext/**/*.po")

      {igniter, conflicts} =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&Source.get(&1, :path))
        |> Enum.filter(&(String.starts_with?(&1, "priv/gettext/") and Path.basename(Path.dirname(&1)) == "LC_MESSAGES"))
        |> Enum.flat_map(fn path ->
          case Regex.named_captures(@context_catalog, Path.basename(path)) do
            %{"domain" => domain, "context" => context} ->
              [{Path.join(Path.dirname(path), domain <> ".po"), context, path}]

            nil ->
              []
          end
        end)
        |> Enum.filter(fn {target, _context, _path} ->
          privs = Map.get(domains, Path.basename(target, ".po"), [])
          Enum.any?(privs, &BlueprintCatalogs.in_priv?(target, &1))
        end)
        |> Enum.group_by(&elem(&1, 0), fn {_target, context, path} -> {@context_order[context], path} end)
        |> Enum.sort()
        |> Enum.reduce({igniter, []}, fn {target, sources}, {igniter, conflicts} ->
          paths = sources |> Enum.sort() |> Enum.map(&elem(&1, 1))
          {igniter, found} = carry_translations(igniter, target, paths)
          {igniter, conflicts ++ found}
        end)

      case conflicts do
        [] ->
          igniter

        conflicts ->
          Igniter.add_warning(igniter, """
          These messages were translated differently in a Blueprint's old naming,
          forms and listings catalogs. The first was copied to the new catalog;
          check it:

          #{Enum.map_join(conflicts, "\n", fn {target, msgid, kept, other} -> "  #{target}: #{inspect(msgid)} kept #{inspect(kept)}, not #{inspect(other)}" end)}
          """)
      end
    end

    defp carry_translations(igniter, target, paths) do
      sources = for path <- paths, {:ok, catalog} <- [parse_catalog(igniter, path)], do: catalog
      exists? = Igniter.exists?(igniter, target)
      igniter = if exists?, do: Igniter.include_existing_file(igniter, target), else: igniter

      with [first | _] <- sources,
           {:ok, catalog} <- if(exists?, do: parse_catalog(igniter, target), else: {:ok, %{first | messages: []}}) do
        {messages, conflicts} =
          sources
          |> Enum.flat_map(& &1.messages)
          |> Enum.filter(&translated?/1)
          |> Enum.reduce({catalog.messages, []}, &carry_message(&1, &2, target))

        cond do
          messages == catalog.messages ->
            {igniter, conflicts}

          exists? ->
            {Igniter.update_file(igniter, target, &Source.update(&1, :content, compose(catalog, messages))), conflicts}

          true ->
            {Igniter.create_new_file(igniter, target, compose(catalog, messages)), conflicts}
        end
      else
        _ -> {igniter, []}
      end
    end

    defp carry_message(message, {messages, conflicts}, target) do
      case Enum.find_index(messages, &Expo.Message.same?(&1, message)) do
        nil ->
          {messages ++ [message], conflicts}

        index ->
          existing = Enum.at(messages, index)

          cond do
            not translated?(existing) -> {List.replace_at(messages, index, message), conflicts}
            translation(existing) == translation(message) -> {messages, conflicts}
            true -> {messages, conflicts ++ [{target, msgid(message), shown(existing), shown(message)}]}
          end
      end
    end

    defp parse_catalog(igniter, path) do
      igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content) |> Expo.PO.parse_string()
    end

    defp compose(catalog, messages), do: %{catalog | messages: messages} |> Expo.PO.compose() |> IO.iodata_to_binary()

    defp translated?(message), do: Enum.any?(translation(message), &(&1 != ""))

    defp translation(%Expo.Message.Singular{msgstr: msgstr}), do: [IO.iodata_to_binary(msgstr)]

    defp translation(%Expo.Message.Plural{msgstr: msgstr}),
      do: msgstr |> Enum.sort() |> Enum.map(fn {_index, value} -> IO.iodata_to_binary(value) end)

    defp msgid(message), do: IO.iodata_to_binary(message.msgid)
    defp shown(message), do: message |> translation() |> Enum.join(" / ")

    @doc """
    Completes `Plural-Forms` headers in `priv/gettext/**/*.po`.

    Gettext 1.0 warns, once per catalog per compile, on a header it cannot
    parse: `nplurals=2;` without the rule, or a rule without its trailing `;`.
    An incomplete header for a locale Expo knows is replaced with the full
    one. For other locales a missing `;` is added and a bare `nplurals=2;`
    gets the two-form rule `plural=(n != 1);`, with a warning to check it;
    any other header is reported.
    """
    def complete_plural_forms_headers(igniter) do
      igniter = Igniter.include_glob(igniter, "priv/gettext/**/*.po")

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.filter(&(String.starts_with?(&1, "priv/gettext/") and Path.extname(&1) == ".po"))
      |> Enum.sort()
      |> Enum.reduce(igniter, fn path, igniter ->
        content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

        case Regex.run(@plural_forms_header, content, capture: :all_but_first) do
          [header] -> complete_plural_forms_header(igniter, path, header)
          nil -> igniter
        end
      end)
    end

    defp complete_plural_forms_header(igniter, path, header) do
      locale = catalog_locale(path)

      with {:error, _} <- PluralForms.parse(header),
           {:ok, plural_forms} <- PluralForms.plural_form(locale) do
        put_plural_forms(igniter, path, header, PluralForms.to_string(plural_forms))
      else
        {:ok, %PluralForms{}} -> igniter
        :error -> complete_unknown_plural_forms(igniter, path, header, locale)
      end
    end

    @two_forms "nplurals=2; plural=(n != 1);"

    # Country codes written where the language code belongs. Gettext knows the
    # language, not the country.
    @language_for_country %{
      "cn" => "zh",
      "cz" => "cs",
      "dk" => "da",
      "ee" => "et",
      "gb" => "en",
      "gr" => "el",
      "jp" => "ja",
      "kr" => "ko",
      "rs" => "sr",
      "ua" => "uk",
      "us" => "en"
    }

    # A locale Gettext does not know: a rule only missing its `;` gets one, and
    # a bare `nplurals=2;` the two-form rule nearly every two-form language
    # uses. Anything else is left for a person.
    defp complete_unknown_plural_forms(igniter, path, header, locale) do
      terminated = String.trim_trailing(header) <> ";"
      unknown = unknown_locale(locale)

      cond do
        not String.ends_with?(header, ";") and match?({:ok, _}, PluralForms.parse(terminated)) ->
          put_plural_forms(igniter, path, header, terminated)

        header =~ ~r/^nplurals\s*=\s*2\s*;?$/ ->
          igniter
          |> put_plural_forms(path, header, @two_forms)
          |> Igniter.add_warning("""
          #{path} had an incomplete Plural-Forms header (#{header}). #{unknown}
          It was completed with the two-form rule `#{@two_forms}`; check that it fits the language.
          """)

        true ->
          Igniter.add_warning(igniter, """
          #{path} has an incomplete Plural-Forms header (#{header}). #{unknown}
          Complete it, for example `#{@two_forms}`, or remove the header.
          """)
      end
    end

    defp unknown_locale(locale) do
      case Map.fetch(@language_for_country, locale) do
        {:ok, language} -> "#{locale} is not a locale Gettext knows; did you mean #{language}?"
        :error -> "#{locale} is not a locale Gettext knows."
      end
    end

    defp put_plural_forms(igniter, path, header, complete) do
      Igniter.update_file(igniter, path, &Source.update(&1, :content, replace_plural_forms(&1, header, complete)))
    end

    defp replace_plural_forms(source, header, complete) do
      Regex.replace(@plural_forms_header, Source.get(source, :content), fn line, _header ->
        String.replace(line, header, complete, global: false)
      end)
    end

    # priv/gettext/<locale>/LC_MESSAGES/x.po or priv/gettext/<backend>/<locale>/LC_MESSAGES/x.po
    defp catalog_locale(path) do
      path
      |> Path.split()
      |> Enum.take_while(&(&1 != "LC_MESSAGES"))
      |> List.last()
    end

    def configure_swoosh_client(igniter) do
      Config.configure_new(
        igniter,
        "config.exs",
        :swoosh,
        [:api_client],
        Swoosh.ApiClient.Req
      )
    end

    @doc """
    Moves the endpoint to the end of the application's `children`.

    Started last, it stops first: shutting down, it drains its sockets with
    close code 1012 and clients reconnect. Stopped after presence and Brando,
    the admin socket is closed with 1000 instead, and phoenix.js does not
    reconnect after a normal close, so editors drop out of presence until they
    reload. (`add_new_child`'s `after:` cannot place a child just before the
    last one, so the endpoint moves instead.)
    """
    def start_endpoint_last(igniter, application \\ nil, endpoint \\ nil) do
      application =
        application || Igniter.Project.Application.app_module(igniter) ||
          ProjectModule.module_name(igniter, "Application")

      endpoint = endpoint || Module.concat(Igniter.Libs.Phoenix.web_module(igniter), Endpoint)

      case ProjectModule.module_exists(igniter, application) do
        {true, igniter} ->
          ProjectModule.find_and_update_module!(igniter, application, &endpoint_last(&1, endpoint))

        {false, igniter} ->
          igniter
      end
    end

    defp endpoint_last(zipper, endpoint) do
      case Zipper.find(zipper, &children_assignment?/1) do
        nil ->
          {:ok, zipper}

        found ->
          {:ok, Zipper.update(found, fn {:=, meta, [lhs, rhs]} -> {:=, meta, [lhs, move_last(rhs, endpoint)]} end)}
      end
    end

    defp children_assignment?({:=, _, [{:children, _, context}, _]}) when is_atom(context), do: true
    defp children_assignment?(_), do: false

    defp move_last({:__block__, meta, [items]}, endpoint) when is_list(items),
      do: {:__block__, meta, [move_last(items, endpoint)]}

    defp move_last(items, endpoint) when is_list(items) do
      case Enum.split_with(items, &(child_module(&1) == endpoint)) do
        {[], _rest} ->
          items

        {endpoints, rest} ->
          # Comments are printed by line, so the moved child takes lines
          # after the last one, its comments with it
          last_line = rest |> Enum.map(&last_line/1) |> Enum.max(fn -> 0 end)
          rest ++ Enum.map(endpoints, &renumber(&1, last_line + 1))
      end
    end

    defp move_last(other, _endpoint), do: other

    defp last_line(quoted) do
      {_, line} =
        Macro.prewalk(quoted, 0, fn
          {_, meta, _} = node, line when is_list(meta) -> {node, max(line, meta[:line] || 0)}
          node, line -> {node, line}
        end)

      line
    end

    defp renumber(quoted, first_line) do
      shift = first_line - first_line(quoted)

      Macro.prewalk(quoted, fn
        {form, meta, args} when is_list(meta) -> {form, shift_meta(meta, shift), args}
        node -> node
      end)
    end

    defp first_line({_, meta, _} = quoted) when is_list(meta) do
      comment_lines = meta |> Keyword.get(:leading_comments, []) |> Enum.map(& &1.line)
      Enum.min([last_line(quoted) | comment_lines])
    end

    defp first_line(quoted), do: last_line(quoted)

    defp shift_meta(meta, shift) do
      Enum.map(meta, fn
        {key, line} when key in [:line] and is_integer(line) ->
          {key, line + shift}

        {key, position} when key in [:closing, :end_of_expression, :end, :do] and is_list(position) ->
          {key, Keyword.update(position, :line, nil, &(&1 + shift))}

        {key, comments} when key in [:leading_comments, :trailing_comments] ->
          {key, Enum.map(comments, &%{&1 | line: &1.line + shift})}

        other ->
          other
      end)
    end

    defp child_module({:__aliases__, _, parts}) when is_list(parts), do: Module.concat(parts)
    defp child_module({:__block__, _, [{first, _}]}), do: child_module(first)
    defp child_module({:{}, _, [first | _]}), do: child_module(first)
    defp child_module({first, _}), do: child_module(first)
    defp child_module(_), do: nil

    @doc """
    Points Brando at the application's Swoosh mailer, `MyApp.Mailer` or
    `mailer` when given, so Brando can send email through it. Writes to
    `config/brando.exs` when the application has one, and leaves an existing
    setting alone. Without the mailer module it does nothing.
    """
    def configure_brando_mailer(igniter, mailer \\ nil) do
      mailer = mailer || ProjectModule.module_name(igniter, "Mailer")

      configured? = Enum.any?(~w(config.exs brando.exs), &Config.configures_key?(igniter, &1, :brando, :mailer))

      case ProjectModule.module_exists(igniter, mailer) do
        {true, igniter} when not configured? ->
          file = if Igniter.exists?(igniter, "config/brando.exs"), do: "brando.exs", else: "config.exs"
          Config.configure_new(igniter, file, :brando, [:mailer], mailer)

        {_exists, igniter} ->
          igniter
      end
    end

    def rewrite_dockerfiles(igniter) do
      igniter
      |> Igniter.include_glob("Dockerfile*")
      |> rewrite_matching_sources(&dockerfile?/1, fn content ->
        Regex.replace(@phx_digest_regex, content, "mix brando.digest")
      end)
    end

    def rewrite_font_urls(igniter) do
      igniter
      |> include_asset_glob("assets/**/*.{css,pcss,sass,scss}")
      |> Igniter.include_glob("lib/**/*.{eex,ex,exs,heex,leex}")
      |> rewrite_matching_sources(&font_source?/1, fn content ->
        Regex.replace(@font_vsn_regex, content, "\\1")
      end)
    end

    def pin_live_view_javascript(igniter) do
      version = phoenix_live_view_version()

      igniter
      |> Igniter.include_glob("assets/package.json")
      |> include_asset_glob("assets/**/package.json")
      |> rewrite_matching_sources(&assets_package_json?/1, fn content ->
        Regex.replace(@live_view_package_regex, content, fn _match, prefix, suffix ->
          prefix <> version <> suffix
        end)
      end)
    end

    @doc """
    Switches Vite's `build.sourcemap: true` to `'hidden'` in the application's
    asset configs, so built scripts no longer point browsers at their maps.
    `mix brando.digest` deletes the maps before release.
    """
    def hide_source_maps(igniter) do
      igniter
      |> Igniter.include_glob("assets/vite.config.{js,mjs,cjs,ts,mts}")
      |> Igniter.include_glob("assets/*/vite.config.{js,mjs,cjs,ts,mts}")
      |> rewrite_matching_sources(&vite_config?/1, fn content ->
        Regex.replace(@vite_sourcemap_regex, content, "\\1'hidden'")
      end)
    end

    defp phoenix_live_view_version do
      case Application.spec(:phoenix_live_view, :vsn) do
        nil -> @phoenix_live_view_fallback_version
        version -> to_string(version)
      end
    end

    @image_text_extensions ~w(.ex .heex .eex .leex)
    @image_text_limit 50

    @doc """
    Warns about application code that reads an image's `alt`, `title` or
    `credits` as a string. Since 0.55 they are language → text maps, and only
    a person can tell which language each call site means, so this lists
    the places — it rewrites nothing.
    """
    def warn_image_text_reads(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.{ex,heex,eex,leex}")

      sources =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
        |> Enum.filter(fn {path, _content} ->
          String.starts_with?(path, "lib/") and Path.extname(path) in @image_text_extensions
        end)

      assets =
        sources
        |> Enum.filter(fn {_path, content} -> String.contains?(content, "use Brando.Blueprint") end)
        |> Enum.flat_map(fn {_path, content} -> Brando.Images.TextUsage.image_assets(content) end)
        |> Enum.uniq()

      findings =
        for {path, content} <- Enum.sort(sources),
            %{line: line, text: text} <- Brando.Images.TextUsage.scan_code(content, assets),
            do: "#{path}:#{line}: #{text}"

      case findings do
        [] ->
          igniter

        findings ->
          shown = Enum.take(findings, @image_text_limit)
          more = length(findings) - length(shown)

          Igniter.add_warning(igniter, """
          Image alt text, title and credits are now maps of language → text.
          These lines look like they read them as strings (matched by name, so
          check each one):

          #{Enum.map_join(shown, "\n", &("  " <> &1))}#{if more > 0, do: "\n  … and #{more} more", else: ""}

          Read one language with `Brando.Images.text(image, :alt, language)`,
          or all three with `Brando.Images.resolve_texts(image, language)`.
          `<Brando.HTML.picture>` needs nothing: it renders the request's
          language, or `language:` when given.
          """)
      end
    end

    defp rewrite_matching_sources(igniter, path_predicate, content_updater) do
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.filter(path_predicate)
      |> Enum.reduce(igniter, fn path, igniter ->
        Igniter.update_file(igniter, path, fn source ->
          Source.update(source, :content, content_updater)
        end)
      end)
    end

    defp dockerfile?(path) do
      Path.dirname(path) == "." and String.starts_with?(Path.basename(path), "Dockerfile")
    end

    defp font_source?(path) do
      (String.starts_with?(path, "assets/") or String.starts_with?(path, "lib/")) and
        Path.extname(path) in @font_source_extensions and not dependency_path?(path)
    end

    defp vite_config?(path) do
      String.starts_with?(path, "assets/") and String.starts_with?(Path.basename(path), "vite.config.")
    end

    defp assets_package_json?(path) do
      String.starts_with?(path, "assets/") and Path.basename(path) == "package.json" and
        not dependency_path?(path)
    end

    # Installed packages under `assets/` are not the application's source, and
    # a glob over them reads thousands of files, so list the files and leave
    # `node_modules` and Yalc's store out.
    defp include_asset_glob(igniter, glob) do
      if igniter.assigns[:test_mode?] do
        Igniter.include_glob(igniter, glob)
      else
        glob
        |> Path.wildcard()
        |> Enum.reject(&dependency_path?/1)
        |> Enum.reduce(igniter, &Igniter.include_existing_file(&2, &1))
      end
    end

    defp dependency_path?(path), do: path |> Path.split() |> Enum.any?(&(&1 in ["node_modules", ".yalc"]))

    def rewrite_preview_targets(igniter) do
      rewriting_module = Igniter.Libs.Phoenix.web_module_name(igniter, LivePreview)

      case ProjectModule.find_and_update_module(igniter, rewriting_module, &rewrite_preview_module/1) do
        {:ok, igniter} -> igniter
        {:error, igniter} -> igniter
      end
    end

    defp rewrite_preview_module(zipper) do
      Common.update_all_matches(zipper, &preview_target_call?/1, &rewrite_preview_target/1)
    end

    defp rewrite_preview_target(target_zipper) do
      layout_template = collect_layout_template(target_zipper)

      with {:ok, target_zipper} <- replace_layout_modules(target_zipper, layout_template),
           {:ok, target_zipper} <- remove_layout_templates(target_zipper),
           view_module = collect_view_module(target_zipper),
           {:ok, target_zipper} <- replace_view_templates(target_zipper, view_module) do
        remove_view_modules(target_zipper)
      end
    end

    defp replace_layout_modules(zipper, layout_template) do
      Common.update_all_matches(zipper, &layout_module_call?/1, fn zipper ->
        case Zipper.node(zipper) do
          {:layout_module, _metadata, [module_arg]} ->
            new_code =
              quote do
                layout {unquote(module_arg), unquote(layout_template)}
              end

            {:ok, Common.replace_code(zipper, new_code)}

          _other ->
            {:ok, zipper}
        end
      end)
    end

    defp collect_layout_template(zipper) do
      zipper
      |> Common.find_all(&layout_template_call?/1)
      |> List.first()
      |> case do
        nil ->
          :app

        layout_template_zipper ->
          layout_template_zipper
          |> Zipper.node()
          |> Sourceror.get_args()
          |> List.first()
          |> normalize_layout_template()
      end
    end

    defp normalize_layout_template({:__block__, _metadata, [template]}) when is_binary(template) do
      String.replace_suffix(template, ".html", "")
    end

    defp normalize_layout_template(template) when is_binary(template) do
      String.replace_suffix(template, ".html", "")
    end

    defp normalize_layout_template(template), do: template

    defp remove_layout_templates(zipper) do
      zipper
      |> Common.remove_all_matches(&layout_template_call?/1)
      |> then(&{:ok, &1})
    end

    defp replace_view_templates(zipper, nil), do: {:ok, zipper}

    defp replace_view_templates(zipper, view_module) do
      Common.update_all_matches(zipper, &view_template_call?/1, fn zipper ->
        replace_view_template(zipper, view_module)
      end)
    end

    defp replace_view_template(zipper, view_module) do
      case Zipper.node(zipper) do
        {:view_template, _metadata, [template_arg]} ->
          {:ok, Common.replace_code(zipper, view_template_code(view_module, template_arg))}

        _other ->
          {:ok, zipper}
      end
    end

    defp view_template_code(view_module, template_arg) do
      if callback_ast?(template_arg) do
        quote do
          template fn entry ->
            {unquote(view_module), unquote(template_arg).(entry)}
          end
        end
      else
        quote do
          template {unquote(view_module), unquote(template_arg)}
        end
      end
    end

    defp collect_view_module(zipper) do
      zipper
      |> Common.find_all(&view_module_call?(&1))
      |> List.first()
      |> case do
        nil -> nil
        view_module_zipper -> view_module_zipper |> Zipper.node() |> Sourceror.get_args() |> List.first()
      end
    end

    defp remove_view_modules(zipper) do
      # Remove all view_module calls
      Common.remove_all_matches(zipper, &view_module_call?(&1))
      |> then(&{:ok, &1})
    end

    defp layout_module_call?(zipper) do
      CodeFunction.function_call?(zipper, :layout_module, 1)
    end

    defp layout_template_call?(zipper) do
      CodeFunction.function_call?(zipper, :layout_template, 1)
    end

    defp view_module_call?(zipper) do
      CodeFunction.function_call?(zipper, :view_module, 1)
    end

    defp view_template_call?(zipper) do
      # Could be `view_template "some_string"` or `view_template fn e -> e.template end`
      CodeFunction.function_call?(zipper, :view_template, 1)
    end

    defp preview_target_call?(zipper) do
      CodeFunction.function_call?(zipper, :preview_target, 2)
    end

    def create_florist_config(igniter) do
      florist_config? = Igniter.exists?(igniter, "florist.config.exs")
      deployment_config? = Igniter.exists?(igniter, "deployment.cfg")
      fabfile? = Igniter.exists?(igniter, "fabfile.py")

      case {florist_config?, deployment_config?, fabfile?} do
        {true, _, _} ->
          igniter

        {false, true, true} ->
          generate_florist_config(igniter)

        {false, false, false} ->
          igniter

        {false, _, _} ->
          Igniter.add_warning(
            igniter,
            "Skipped Florist conversion because both legacy `deployment.cfg` and `fabfile.py` are required."
          )
      end
    end

    defp generate_florist_config(igniter) do
      igniter =
        igniter
        |> Igniter.include_existing_file("deployment.cfg", required?: true)
        |> Igniter.include_existing_file("fabfile.py", required?: true)

      deployment_config = source_content(igniter, "deployment.cfg")
      fabfile = source_content(igniter, "fabfile.py")
      {igniter, legacy_files} = legacy_deployment_files(igniter)

      case FloristConfig.generate(deployment_config, fabfile, legacy_files) do
        {:ok, content, warnings} ->
          igniter
          |> Igniter.create_new_file("florist.config.exs", content, on_exists: :skip)
          |> add_health_plug()
          |> add_florist_warnings(warnings)
          |> Igniter.add_notice(
            "Created `florist.config.exs` from the legacy Fabric files. Review it before use; the source files were retained."
          )

        {:error, reason} ->
          Igniter.add_warning(igniter, "Could not create `florist.config.exs`: #{reason}")
      end
    end

    @doc """
    Adds `plug Brando.Plug.Health` to the endpoint, before the router.

    Florist's deploy and its nginx templates check `/health`; without the plug
    the request falls through to the router and the check never passes.
    """
    def add_health_plug(igniter, endpoint \\ nil) do
      endpoint = endpoint || default_endpoint(igniter)
      missing = "add `plug Brando.Plug.Health` to #{inspect(endpoint)}, before the router. Florist checks /health."
      add_endpoint_plug(igniter, endpoint, Brando.Plug.Health, missing)
    end

    @content_plugs [
      {Brando.Plug.Markdown, "serves entries as Markdown at their URL + .md"},
      {Brando.Plug.IndexNow, "serves the IndexNow key file"}
    ]

    @doc """
    Adds `plug Brando.Plug.Markdown` and `plug Brando.Plug.IndexNow` to the
    endpoint, before the router, in that order. Both act before routing: an
    entry's `.md` URL loses its extension before the router matches it, and
    the IndexNow key file is answered without reaching it. They go before
    `Brando.Plug.Health` when the endpoint has it, as in the install
    template. A plug the endpoint already has is left where it is.
    """
    def add_content_plugs(igniter, endpoint \\ nil) do
      endpoint = endpoint || default_endpoint(igniter)

      case ProjectModule.module_exists(igniter, endpoint) do
        {true, igniter} ->
          Enum.reduce(@content_plugs, igniter, fn {plug, purpose}, igniter ->
            missing = "add `plug #{inspect(plug)}` to #{inspect(endpoint)}, before the router. It #{purpose}."
            add_endpoint_plug(igniter, endpoint, plug, missing)
          end)

        {false, igniter} ->
          Igniter.add_warning(igniter, """
          Could not find the endpoint #{inspect(endpoint)}; add `plug Brando.Plug.Markdown` and
          `plug Brando.Plug.IndexNow` to it, before the router.
          """)
      end
    end

    defp default_endpoint(igniter), do: Module.concat(Igniter.Libs.Phoenix.web_module(igniter), Endpoint)

    defp add_endpoint_plug(igniter, endpoint, plug, missing) do
      # Updating a module reformats its file, so an endpoint that already has
      # the plug is only read.
      with {:ok, {igniter, _source, defmodule}} <- ProjectModule.find_module(igniter, endpoint),
           {:ok, body} <- Common.move_to_do_block(defmodule),
           :error <- move_to_plug(body, &Common.nodes_equal?(&1, plug)) do
        case ProjectModule.find_and_update_module(igniter, endpoint, &plug_before_router(&1, plug, missing)) do
          {:ok, igniter} -> igniter
          {:error, igniter} -> Igniter.add_warning(igniter, "Could not find the endpoint; " <> missing)
        end
      else
        {:ok, _plug} -> igniter
        {:error, igniter} -> Igniter.add_warning(igniter, "Could not find the endpoint; " <> missing)
        :error -> Igniter.add_warning(igniter, "Could not read the endpoint; " <> missing)
      end
    end

    defp plug_before_router(zipper, plug, missing) do
      with :error <- health_plug(zipper, plug),
           :error <- move_to_plug(zipper, &router?/1) do
        {:warning, "Could not find the router plug; " <> missing}
      else
        {:ok, anchor} -> {:ok, Common.add_code(anchor, "plug #{inspect(plug)}", placement: :before)}
      end
    end

    defp health_plug(_zipper, Brando.Plug.Health), do: :error
    defp health_plug(zipper, _plug), do: move_to_plug(zipper, &Common.nodes_equal?(&1, Brando.Plug.Health))

    defp move_to_plug(zipper, predicate) do
      CodeFunction.move_to_function_call_in_current_scope(zipper, :plug, [1, 2], fn call ->
        CodeFunction.argument_matches_predicate?(call, 0, predicate)
      end)
    end

    defp router?(zipper) do
      case Zipper.node(zipper) do
        {:__aliases__, _, parts} -> Enum.join(parts, ".") =~ ~r/(^|\.)Router$/
        _other -> false
      end
    end

    # Fills the domains, ports and process manager deployment.cfg leaves out.
    # Only BRANDO_URL_HOST/PORT are read from the .envrc files.
    @legacy_deployment_globs ["etc/nginx/*.conf", "etc/supervisord/*.conf", "etc/systemd/*.service"]
    @legacy_deployment_file ~r{^(\.envrc\.[^/]+|etc/(nginx|supervisord)/[^/]+\.conf|etc/systemd/[^/]+\.service)$}

    defp legacy_deployment_files(igniter) do
      igniter = Enum.reduce(@legacy_deployment_globs, igniter, &Igniter.include_glob(&2, &1))
      igniter = Enum.reduce(envrc_paths(igniter), igniter, &Igniter.include_existing_file(&2, &1))

      files =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&Source.get(&1, :path))
        |> Enum.filter(&Regex.match?(@legacy_deployment_file, &1))
        |> Map.new(&{&1, source_content(igniter, &1)})

      {igniter, files}
    end

    # Igniter's globs skip dotfiles.
    defp envrc_paths(igniter) do
      if igniter.assigns[:test_mode?],
        do:
          igniter.assigns |> Map.get(:test_files, %{}) |> Map.keys() |> Enum.filter(&String.starts_with?(&1, ".envrc.")),
        else: Path.wildcard(".envrc.*", match_dot: true)
    end

    defp source_content(igniter, path) do
      igniter.rewrite
      |> Rewrite.source!(path)
      |> Source.get(:content)
    end

    defp add_florist_warnings(igniter, warnings) do
      Enum.reduce(warnings, igniter, &Igniter.add_warning(&2, "Florist migration: #{&1}"))
    end

    @doc """
    Moves `use Gettext, otp_app: ...` backends to `use Gettext.Backend` and
    their importers to `use Gettext, backend: ...`, as Igniter's
    `igniter.update_gettext` does.

    It is composed here rather than scheduled as a separate task: that task
    compiles the application first, and it pins `gettext ~> 0.26` in
    `mix.exs`. The application must already require Gettext 1.0 to fetch the
    new Brando, so the requirement is left as it was.
    """
    def update_gettext_backends(igniter) do
      igniter = Igniter.include_existing_file(igniter, "mix.exs")
      mix_exs = igniter.rewrite |> Rewrite.source!("mix.exs") |> Source.get(:content)

      igniter
      |> Mix.Tasks.Igniter.UpdateGettext.igniter()
      |> Igniter.update_file("mix.exs", &Source.update(&1, :content, mix_exs))
    end

    @doc """
    Creates the Gettext recovery helper.

    An existing copy of the current helper is kept, and a copy of a helper an
    earlier Brando shipped is replaced. A copy that matches neither was edited
    by the application: it is left alone with a warning rather than aborting
    the whole source upgrade.
    """
    def copy_gettext_script(igniter) do
      contents = gettext_script()

      if Igniter.exists?(igniter, @gettext_script_path) do
        igniter = Igniter.include_existing_file(igniter, @gettext_script_path)
        current = igniter.rewrite |> Rewrite.source!(@gettext_script_path) |> Source.get(:content)

        cond do
          same_script?(current, contents) ->
            igniter

          Enum.any?(legacy_gettext_scripts(), &same_script?(current, &1)) ->
            Igniter.update_file(igniter, @gettext_script_path, &Source.update(&1, :content, contents))

          true ->
            Igniter.add_warning(igniter, """
            #{@gettext_script_path} differs from every version Brando shipped, so it was left unchanged.
            Compare it with priv/templates/brando.migrate/sync_gettext.sh in Brando before using it.
            """)
        end
      else
        Igniter.create_new_file(igniter, @gettext_script_path, contents)
      end
    end

    defp same_script?(left, right), do: String.trim_trailing(left) == String.trim_trailing(right)

    defp legacy_gettext_scripts do
      :brando
      |> Application.app_dir(["priv", "templates", "brando.migrate", "legacy_sync_gettext", "*.sh"])
      |> Path.wildcard()
      |> Enum.map(&File.read!/1)
    end

    @doc """
    Replaces the Gettext recovery helper with the current version.

    The helper is Brando-owned and was copied by earlier upgrade tasks, so a
    later task may overwrite it. The diff is still part of the reviewed plan.
    """
    def refresh_gettext_script(igniter) do
      contents = gettext_script()

      if Igniter.exists?(igniter, @gettext_script_path) do
        Igniter.update_file(igniter, @gettext_script_path, &Source.update(&1, :content, contents))
      else
        Igniter.create_new_file(igniter, @gettext_script_path, contents)
      end
    end

    defp gettext_script do
      :brando
      |> Application.app_dir(["priv", "templates", "brando.migrate"])
      |> Path.join("sync_gettext.sh")
      |> File.read!()
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
