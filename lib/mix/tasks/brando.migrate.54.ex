if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Migrate54 do
    use Igniter.Mix.Task

    alias Brando.Migration.FloristConfig
    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Config
    alias Igniter.Refactors.Rename
    alias Rewrite.Source
    alias Sourceror.Zipper

    @font_source_extensions ~w(.css .eex .ex .exs .heex .leex .pcss .sass .scss)
    @font_vsn_regex ~r/(\.(?:woff2?|ttf|otf|eot))\?vsn=d\b/
    @live_view_package_regex ~r/("phoenix_live_view"\s*:\s*")[^"]+("\s*[,}])/
    @phx_digest_regex ~r/\bmix[\t ]+phx\.digest(?=[\t ]|$)/m
    @phoenix_live_view_fallback_version "1.2.8"

    @listing_core_components ~w(<.field <.i18n <.update_link <.url)

    @shortdoc "Migrates application source to Brando 0.54"
    @moduledoc """
    #{@shortdoc}.

    Run this task from a clean, committed worktree after updating the Brando
    dependency. It rewrites legacy Blueprint and LivePreview syntax, preserves
    legacy Meta and JSON-LD path extraction semantics, copies the current
    `mix brando.upgrade` task and gettext recovery helper, and schedules
    Igniter's Gettext source upgrade.

    The task changes source files only. Review and compile its diff before
    generating or running database migrations. The complete ordered workflow is
    documented in `guides/migrating_to_054.md` and the 0.54 changelog.
    """

    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando}
    end

    def igniter(igniter) do
      igniter = rewrite_legacy_function_calls(igniter)
      {igniter, modules} = find_blueprints(igniter)

      igniter =
        Enum.reduce(modules, igniter, &rewrite_blueprint/2)

      igniter
      |> configure_repo_module()
      |> configure_swoosh_client()
      |> rewrite_dockerfiles()
      |> rewrite_font_urls()
      |> pin_live_view_javascript()
      |> rewrite_preview_targets()
      |> create_florist_config()
      |> copy_gettext_script()
      |> copy_updated_migration_script()
      |> Igniter.add_task("igniter.update_gettext")
      |> add_notices()
      |> add_warnings()
    end

    defp rewrite_blueprint(module, igniter) do
      process_module(igniter, module, &rewrite_blueprint_source/1)
    end

    defp rewrite_blueprint_source(zipper) do
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
        add_listing_component_imports(zipper)
      end
    end

    defp process_module(igniter, module, fun) do
      Igniter.Project.Module.find_and_update_module!(igniter, module, fun)
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

    defp add_listing_component_imports(zipper) do
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
          [] ->
            {:ok, zipper}

          imports ->
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
      else
        {:ok, zipper}
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
            if literal_list?(path_or_function) do
              {:ok, replace_path_field(zipper, targets, nil, path_or_function)}
            else
              {:ok, rename_call(zipper, :field)}
            end
        end
      end)
    end

    defp rewrite_json_ld_field(zipper) do
      Common.update_all_matches(zipper, &json_ld_field?(&1), fn zipper ->
        case zipper |> Zipper.node() |> Sourceror.get_args() do
          [name, reference] ->
            {:ok, rewrite_json_ld_reference(zipper, name, reference)}

          [name, type, path, mutator] ->
            {:ok, replace_path_field(zipper, name, type, path, mutator)}

          [name, type, path_or_function] ->
            if literal_list?(path_or_function) do
              {:ok, replace_path_field(zipper, name, type, path_or_function)}
            else
              {:ok, rename_call(zipper, :field)}
            end
        end
      end)
    end

    defp rewrite_json_ld_reference(zipper, name, reference) do
      case reference_target(reference) do
        {:ok, target} ->
          if literal_atom_value(target) == :identity do
            replacement =
              quote do
                field unquote(name), :identity
              end

            Common.replace_code(zipper, replacement)
          else
            replacement =
              quote do
                field unquote(name), :string, fn _entry ->
                  %{"@id" => "#{Brando.Utils.hostname()}/##{unquote(target)}"}
                end
              end

            Common.replace_code(zipper, replacement)
          end

        :error ->
          rename_call(zipper, :field)
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
      Igniter.Project.Module.find_all_matching_modules(igniter, fn _module, zipper ->
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

    defp rewrite_legacy_function_calls(igniter) do
      Rename.rename_function(
        igniter,
        {Brando.Villain, :list_villains},
        {Brando.Villain, :list_blocks},
        arity: 0
      )
    end

    defp configure_repo_module(igniter) do
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

    defp configure_swoosh_client(igniter) do
      Config.configure_new(
        igniter,
        "config.exs",
        :swoosh,
        [:api_client],
        Swoosh.ApiClient.Req
      )
    end

    defp rewrite_dockerfiles(igniter) do
      igniter
      |> Igniter.include_glob(Path.expand("Dockerfile*"))
      |> rewrite_matching_sources(&dockerfile?/1, fn content ->
        Regex.replace(@phx_digest_regex, content, "mix brando.digest")
      end)
    end

    defp rewrite_font_urls(igniter) do
      igniter
      |> Igniter.include_glob(Path.expand("assets/**/*.{css,pcss,sass,scss}"))
      |> Igniter.include_glob(Path.expand("lib/**/*.{eex,ex,exs,heex,leex}"))
      |> rewrite_matching_sources(&font_source?/1, fn content ->
        Regex.replace(@font_vsn_regex, content, "\\1")
      end)
    end

    defp pin_live_view_javascript(igniter) do
      version = phoenix_live_view_version()

      igniter
      |> Igniter.include_glob(Path.expand("assets/package.json"))
      |> Igniter.include_glob(Path.expand("assets/**/package.json"))
      |> rewrite_matching_sources(&assets_package_json?/1, fn content ->
        Regex.replace(@live_view_package_regex, content, fn _match, prefix, suffix ->
          prefix <> version <> suffix
        end)
      end)
    end

    defp phoenix_live_view_version do
      case Application.spec(:phoenix_live_view, :vsn) do
        nil -> @phoenix_live_view_fallback_version
        version -> to_string(version)
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

    defp assets_package_json?(path) do
      String.starts_with?(path, "assets/") and Path.basename(path) == "package.json"
    end

    defp rewrite_preview_targets(igniter) do
      rewriting_module = Igniter.Libs.Phoenix.web_module_name(igniter, LivePreview)

      case Igniter.Project.Module.find_and_update_module(igniter, rewriting_module, &rewrite_preview_module/1) do
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

    defp add_notices(igniter) do
      Igniter.add_notice(igniter, """
      Brando 0.54 source migration prepared.

      In addition to the Blueprint and LivePreview rewrites, the task converts
      legacy list, single, and selection datasources; expands listing filters,
      actions, selection actions, and supported exports into Spark blocks; and
      preserves Meta and JSON-LD path/mutator behavior. Custom listing rows get
      the narrow component imports they use.

      The task also updates `Brando.Villain.list_villains/0`, legacy listing
      `filter:` keys, root Docker digest commands, font cache suffixes, and the
      declared `phoenix_live_view` JavaScript dependency under `assets/`. It
      adds the Brando Repo configuration when exactly one Ecto Repo is
      available and adds Req as Swoosh's API client when none is configured.

      When both legacy `deployment.cfg` and `fabfile.py` exist and no Florist
      configuration exists, the task also creates a reviewable
      `florist.config.exs`. It preserves the legacy single-release/nginx model,
      does not copy passwords, and leaves the legacy files untouched.

      Tenancy remains opt-in. Applications adopting named environments can run
      `mix brando.setup.tenancy` after this general source upgrade to prepare
      their configuration, router pipelines, and tenant migration support.

      Continue in this order:

        1. Review the complete Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`.
        2. If `florist.config.exs` was created, set its required password
           environment variables and complete the deployment review in the
           migration guide before running Florist.
        3. Run `mix brando.upgrade` to copy missing Brando Ecto migrations.
        4. For every application Blueprint with generated migration history,
           run `mix brando.gen.blueprint_migration MyApp.Domain.Schema`.
        5. Review every generated `up/0` and `down/0`, test rollback/forward,
           and commit the source, migrations, and snapshots together.
        6. Run `mix ecto.migrate` only after that review.
        7. After the database migration, run `mix brando.entries.resave` and
           `mix brando.identifiers.sync`.

      See `guides/migrating_to_054.md` and `guides/blueprint_migrations.md` in
      Brando for the full recovery, rebaseline, and gettext instructions.
      """)
    end

    defp add_warnings(igniter) do
      Igniter.add_warning(igniter, """
      Manual 0.54 decisions remain:

        * Add `persist_identifier false` to every Blueprint that must not create
          persisted identifiers. Persistence defaults to true.
        * Table, primary-key, and existing column-level primary-key changes are
          never inferred. Write the Ecto migration, verify the live schema, then
          use the documented Blueprint `--rebaseline` workflow.
        * Search for `Brando.Type.Video` and legacy embedded video values. Moving
          them to `Brando.Videos.Video` requires an application-specific schema
          and data migration; a module-name substitution would corrupt storage.
        * Review application templates for legacy ref paths such as
          `refs.name.data.data.path` and `gallery_images`. Brando migrations
          update database-stored module and fragment code, but cannot identify
          the semantics of every source-controlled template.
        * Update code that traverses generated `*_identifiers` associations for
          `:entries` relations. The relation now exposes its join entries
          directly, and application query/preload intent cannot be inferred.
        * The task rewrites `use Brando.Datasource` only inside Blueprint
          modules. Search for any remaining uses in standalone Ecto schemas and
          move those datasource declarations onto the appropriate Blueprint.
        * Legacy listing `field`, `template`, and positional `child_listing`
          declarations require an application-specific row component or child
          schema. Exports using the removed `after_export` callback and action
          option sets beyond `default_actions:` also remain for manual redesign.
        * Vite 5 manifest configuration, custom Sharp-based processing, merged
          admin Create/Update LiveViews, `<.head>` adoption, and navigation markup
          depend on the application's frontend and custom code. Apply the
          corresponding 0.54 changelog instructions manually where relevant.
        * The task pins declared `phoenix_live_view` dependencies in
          `assets/**/package.json` to the loaded server version. Review any
          nonstandard frontend manifest, refresh the package-manager lockfile,
          and rebuild assets. If application code directly uses Hackney, add it
          explicitly; the Req Swoosh default only replaces Swoosh's client.
        * Custom admin components must repoint form primitives and image, file,
          and video drawer calls from `BrandoAdmin.Components.Form` to
          `Form.Primitives`, `Form.ImageDrawer`, `Form.FileDrawer`, or
          `Form.VideoDrawer` as documented. Markup aliases and local component
          names are application-specific, so the task does not guess them.
        * Review callers of `Brando.Videos.Uploader.initiate_upload/3`, provider
          credential failures, and `Brando.CDN.key_exists?/2`. The CDN replacement
          is `key_available?/2` with inverted and deliberately safer error
          semantics; a mechanical function rename would be unsafe.
        * Move function-based asset `config_target` callbacks from helper modules
          onto their Blueprint schema. The hardened resolver rejects plain helper
          modules and there is no safe target schema the task can choose.
        * Fabric deployments must ensure the application database role owns the
          `oban_job_state` enum before `brando_153` upgrades Oban to v14. Follow
          the changelog's updated `grant_db`/`ALTER TYPE ... OWNER TO` procedure.
        * A generated Florist configuration deliberately retains `:single`
          deployment with nginx. Validate domains, Docker/release paths, remote
          directories, systemd/nginx behavior, the persistent media symlink, and
          database backups before replacing Fabric. Opt into blue/green only as
          a separately rehearsed deployment change. Legacy rclone credentials
          and bucket paths are never inferred.
        * Back up Gettext catalogs before attempting recovery. After extracting
          the backend and frontend catalogs, run the copied helper explicitly
          with Bash, for example:

              bash scripts/sync_gettext.sh priv/gettext/backend/no/LC_MESSAGES

          Review its diff; it only fills empty single-line translations from
          sibling `.po` files and cannot decide plural or contextual translations.
      """)
    end

    defp create_florist_config(igniter) do
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

      case FloristConfig.generate(deployment_config, fabfile) do
        {:ok, content, warnings} ->
          igniter
          |> Igniter.create_new_file("florist.config.exs", content, on_exists: :skip)
          |> add_florist_warnings(warnings)
          |> Igniter.add_notice(
            "Created `florist.config.exs` from the legacy Fabric files. Review it before use; the source files were retained."
          )

        {:error, reason} ->
          Igniter.add_warning(igniter, "Could not create `florist.config.exs`: #{reason}")
      end
    end

    defp source_content(igniter, path) do
      igniter.rewrite
      |> Rewrite.source!(path)
      |> Source.get(:content)
    end

    defp add_florist_warnings(igniter, warnings) do
      Enum.reduce(warnings, igniter, &Igniter.add_warning(&2, "Florist migration: #{&1}"))
    end

    defp copy_gettext_script(igniter) do
      src_file =
        :brando
        |> Application.app_dir(["priv", "templates", "brando.migrate"])
        |> Path.join("sync_gettext.sh")

      Igniter.copy_template(
        igniter,
        src_file,
        "scripts/sync_gettext.sh",
        [],
        on_exists: :overwrite
      )
    end

    defp copy_updated_migration_script(igniter) do
      src_file =
        :brando
        |> Application.app_dir(["priv", "templates", "brando.install", "lib", "mix"])
        |> Path.join("brando.upgrade.ex")

      Igniter.copy_template(
        igniter,
        src_file,
        "lib/mix/brando.upgrade.ex",
        [],
        on_exists: :overwrite
      )
    end
  end
end
