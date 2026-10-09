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

    alias Brando.Deprecated.RenamedModules
    alias Expo.PluralForms
    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Config
    alias Igniter.Project.Module, as: ProjectModule
    alias Igniter.Refactors.Rename
    alias Mix.Brando.Igniter.FloristConfig
    alias Rewrite.Source
    alias Sourceror.Zipper

    @font_source_extensions ~w(.css .eex .ex .exs .heex .leex .pcss .sass .scss)
    @font_vsn_regex ~r/(\.(?:woff2?|ttf|otf|eot))\?vsn=d\b/
    @live_view_package_regex ~r/("phoenix_live_view"\s*:\s*")[^"]+("\s*[,}])/
    @phx_digest_regex ~r/\bmix[\t ]+phx\.digest(?=[\t ]|$)/m
    @vite_sourcemap_regex ~r/(?<![\w$])(sourcemap\s*:\s*)true\b/
    @phoenix_live_view_fallback_version "1.2.12"

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
           {:ok, zipper} <- remove_villain_attributes(zipper) do
        add_villain_relations(zipper, villain_fields)
      end
    end

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

          new_datasource =
            quote do
              datasource unquote(key) do
                type :single

                get fn identifier ->
                  unquote(get_callback).(to_string(__MODULE__), identifier)
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

    defp remove_use_datasource(zipper) do
      {:ok, Common.remove_all_matches(zipper, &use_datasource?(&1))}
    end

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
          quote do
            fn entry ->
              value = get_in(entry, unquote(access_path))
              unquote(mutator).(value)
            end
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

    defp find_blueprints(igniter) do
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

    def rename_list_villains(igniter) do
      Rename.rename_function(
        igniter,
        {Brando.Villain, :list_villains},
        {Brando.Villain, :list_blocks},
        arity: 0
      )
    end

    @doc """
    Points references to the public modules renamed in 0.55 at their new
    names (`Brando.Deprecated.RenamedModules`): routers, sockets, endpoint
    config and code under `config/`, `lib/` and `test/`.

    The source is read as code and only the module names are replaced, so
    `Brando.Meta.HTML` is not `Brando.Meta`, and the rest of a file keeps its
    formatting. A plain `alias` whose last segment changes renames the short
    name in that file too. An alias inside braces that the new name cannot
    share (`alias Brando.{LobbyChannel}`, now `BrandoAdmin`) is left for the
    developer and reported; the old name keeps working until 0.57.
    """
    def rename_moved_modules(igniter) do
      renamed = RenamedModules.all()
      igniter = Igniter.include_glob(igniter, "{config,lib,test}/**/*.{ex,exs}")

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.filter(&(String.starts_with?(&1, ["config/", "lib/", "test/"]) and Path.extname(&1) in [".ex", ".exs"]))
      |> Enum.sort()
      |> Enum.reduce(igniter, &rename_modules_in(&2, &1, renamed))
    end

    defp rename_modules_in(igniter, path, renamed) do
      content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

      case module_rename_patches(content, renamed) do
        {[], []} ->
          igniter

        {patches, left} ->
          igniter
          |> Igniter.update_file(
            path,
            &Source.update(&1, :content, fn content -> Sourceror.patch_string(content, patches) end)
          )
          |> warn_braced_renames(path, left)
      end
    end

    # `{patches, left}`: a patch per renamed module name in the file, and
    # the braced aliases the new names cannot share
    defp module_rename_patches(content, renamed) do
      case Sourceror.parse_string(content) do
        {:ok, ast} ->
          short = ast |> plain_renamed_aliases(renamed) |> short_renames(renamed)

          {_ast, {patches, left}} =
            Macro.prewalk(ast, {[], []}, fn node, acc -> module_rename_patch(node, renamed, short, acc) end)

          {patches, Enum.reverse(left)}

        {:error, _} ->
          {[], []}
      end
    end

    # The renamed modules a file aliases without `as:`, braces included
    defp plain_renamed_aliases(ast, renamed) do
      {_ast, plain} =
        Macro.prewalk(ast, [], fn
          {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
            {node, [alias_module(parts) | acc]}

          {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
            {node, for({:__aliases__, _, parts} <- children, do: alias_module(base ++ parts)) ++ acc}

          node, acc ->
            {node, acc}
        end)

      Enum.filter(plain, &Map.has_key?(renamed, &1))
    end

    # Short names that change with a plain alias: `alias Brando.Upload`
    # becomes `alias Brando.Uploads.Store`, so `Upload.` becomes `Store.`
    defp short_renames(plain, renamed) do
      for old <- plain,
          old_short = old |> Module.split() |> List.last() |> String.to_atom(),
          new_short = renamed[old] |> Module.split() |> List.last() |> String.to_atom(),
          old_short != new_short,
          into: %{},
          do: {old_short, new_short}
    end

    # The braced alias is handled here, child by child, and not walked again
    defp module_rename_patch({{:., _, [{:__aliases__, _, base}, :{}]}, _, children}, renamed, _short, acc)
         when is_list(children) do
      {:ok, Enum.reduce(children, acc, &braced_rename_patch(&1, base, renamed, &2))}
    end

    defp module_rename_patch({:__aliases__, _, [first | rest] = parts} = node, renamed, short, {patches, left} = acc) do
      cond do
        new = renamed[alias_module(parts)] ->
          {node, {[module_patch(node, inspect(new)) | patches], left}}

        Map.has_key?(short, first) and Enum.all?(rest, &is_atom/1) ->
          {node, {[module_patch(node, Enum.join([short[first] | rest], ".")) | patches], left}}

        true ->
          {node, acc}
      end
    end

    defp module_rename_patch(node, _renamed, _short, acc), do: {node, acc}

    defp braced_rename_patch({:__aliases__, _, parts} = child, base, renamed, {patches, left} = acc) do
      module = alias_module(base ++ parts)
      new = renamed[module]

      cond do
        is_nil(new) -> acc
        new_parts = braced_parts(base, new) -> {[module_patch(child, Enum.join(new_parts, ".")) | patches], left}
        true -> {patches, [module | left]}
      end
    end

    defp braced_rename_patch(_child, _base, _renamed, acc), do: acc

    defp module_patch(node, change), do: Sourceror.Patch.new(Sourceror.get_range(node), change, false)

    defp alias_module(parts) do
      if Enum.all?(parts, &is_atom/1), do: Module.concat(parts)
    end

    # The new name's segments after a brace alias's base, or nil when the
    # new name does not start with it
    defp braced_parts(base, new) do
      new_parts = new |> Module.split() |> Enum.map(&String.to_atom/1)
      if List.starts_with?(new_parts, base), do: Enum.drop(new_parts, length(base))
    end

    defp warn_braced_renames(igniter, _path, []), do: igniter

    defp warn_braced_renames(igniter, path, modules) do
      Igniter.add_warning(igniter, """
      #{path} aliases #{Enum.map_join(modules, ", ", &inspect/1)} inside braces, but 0.55 \
      renamed #{if length(modules) == 1, do: "it", else: "them"} out of that namespace \
      (#{Enum.map_join(modules, ", ", &inspect(RenamedModules.new_name(&1)))}). Alias the new \
      name on its own line; the old name keeps working, with a warning, until 0.57.
      """)
    end

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

    @doc """
    Completes `Plural-Forms` headers in `priv/gettext/**/*.po`.

    Gettext 1.0 warns, once per catalog per compile, on a header it cannot
    parse: `nplurals=2;` without the rule, or a rule without its trailing `;`.
    An incomplete header for a locale Expo knows is replaced with the full
    one; other locales are reported.
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
      with {:error, _} <- PluralForms.parse(header),
           {:ok, plural_forms} <- path |> catalog_locale() |> PluralForms.plural_form() do
        complete = PluralForms.to_string(plural_forms)
        Igniter.update_file(igniter, path, &Source.update(&1, :content, replace_plural_forms(&1, header, complete)))
      else
        {:ok, %PluralForms{}} ->
          igniter

        :error ->
          Igniter.add_warning(igniter, """
          #{path} has an incomplete Plural-Forms header (#{header}) for a locale Gettext does not know.
          Complete it, for example `nplurals=2; plural=(n != 1);`, or remove the header.
          """)
      end
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
      |> Igniter.include_glob("assets/**/*.{css,pcss,sass,scss}")
      |> Igniter.include_glob("lib/**/*.{eex,ex,exs,heex,leex}")
      |> rewrite_matching_sources(&font_source?/1, fn content ->
        Regex.replace(@font_vsn_regex, content, "\\1")
      end)
    end

    def pin_live_view_javascript(igniter) do
      version = phoenix_live_view_version()

      igniter
      |> Igniter.include_glob("assets/package.json")
      |> Igniter.include_glob("assets/**/package.json")
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
        Path.extname(path) in @font_source_extensions
    end

    defp vite_config?(path) do
      String.starts_with?(path, "assets/") and String.starts_with?(Path.basename(path), "vite.config.")
    end

    defp assets_package_json?(path) do
      String.starts_with?(path, "assets/") and Path.basename(path) == "package.json"
    end

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
      endpoint = endpoint || Module.concat(Igniter.Libs.Phoenix.web_module(igniter), Endpoint)
      missing = "add `plug Brando.Plug.Health` to #{inspect(endpoint)}, before the router. Florist checks /health."

      # Updating a module reformats its file, so an endpoint that already has
      # the plug is only read.
      with {:ok, {igniter, _source, defmodule}} <- ProjectModule.find_module(igniter, endpoint),
           {:ok, body} <- Common.move_to_do_block(defmodule),
           :error <- move_to_plug(body, &Common.nodes_equal?(&1, Brando.Plug.Health)) do
        case ProjectModule.find_and_update_module(igniter, endpoint, &health_plug_before_router(&1, missing)) do
          {:ok, igniter} -> igniter
          {:error, igniter} -> Igniter.add_warning(igniter, "Could not find the endpoint; " <> missing)
        end
      else
        {:ok, _health_plug} -> igniter
        {:error, igniter} -> Igniter.add_warning(igniter, "Could not find the endpoint; " <> missing)
        :error -> Igniter.add_warning(igniter, "Could not read the endpoint; " <> missing)
      end
    end

    defp health_plug_before_router(zipper, missing) do
      case move_to_plug(zipper, &router?/1) do
        {:ok, router} -> {:ok, Common.add_code(router, "plug Brando.Plug.Health", placement: :before)}
        :error -> {:warning, "Could not find the router plug; " <> missing}
      end
    end

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
