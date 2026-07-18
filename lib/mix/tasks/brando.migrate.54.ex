if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Migrate54 do
    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Sourceror.Zipper

    @shortdoc "Migrates application source to Brando 0.54"
    @moduledoc """
    #{@shortdoc}.

    Run this task from a clean, committed worktree after updating the Brando
    dependency. It rewrites legacy Blueprint and LivePreview syntax, copies the
    current `mix brando.upgrade` task and gettext recovery helper, and schedules
    Igniter's Gettext source upgrade.

    The task changes source files only. Review and compile its diff before
    generating or running database migrations. The complete ordered workflow is
    documented in `guides/migrating_to_054.md` and the 0.54 changelog.
    """

    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando}
    end

    def igniter(igniter) do
      {igniter, modules} = find_blueprints(igniter)

      igniter =
        Enum.reduce(modules, igniter, &rewrite_blueprint/2)

      igniter
      |> rewrite_preview_targets()
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
           {:ok, zipper} <- rewrite_listing_actions(zipper),
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

    defp process_module(igniter, module, fun) do
      Igniter.Project.Module.find_and_update_module!(igniter, module, fun)
    end

    defp rewrite_legacy_datasources(zipper) do
      if uses_legacy_datasource?(zipper) do
        with {:ok, zipper} <- rewrite_list_datasources(zipper),
             {:ok, zipper} <- rewrite_selection_datasources(zipper) do
          remove_use_datasource(zipper)
        end
      else
        {:ok, zipper}
      end
    end

    defp rewrite_list_datasources(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &list_datasource?(&1),
        fn zipper ->
          {:ok, key_zipper} = Igniter.Code.Function.move_to_nth_argument(zipper, 0)
          key_zipper_node = Sourceror.Zipper.node(key_zipper)
          [key] = Sourceror.get_args(key_zipper_node)

          {:ok, list_fn_zipper} = Igniter.Code.Function.move_to_nth_argument(zipper, 1)
          list_fn_zipper_node = Sourceror.Zipper.node(list_fn_zipper)

          new_datasource =
            quote do
              datasource unquote(key) do
                type :list
                list unquote(list_fn_zipper_node)
              end
            end

          updated_zipper = Igniter.Code.Common.replace_code(zipper, new_datasource)

          {:ok, updated_zipper}
        end
      )
    end

    defp rewrite_selection_datasources(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &selection_datasource?(&1),
        fn zipper ->
          {:ok, key_zipper} = Igniter.Code.Function.move_to_nth_argument(zipper, 0)
          key_zipper_node = Sourceror.Zipper.node(key_zipper)
          [key] = Sourceror.get_args(key_zipper_node)

          {:ok, list_fn_zipper} = Igniter.Code.Function.move_to_nth_argument(zipper, 1)
          list_fn_zipper_node = Sourceror.Zipper.node(list_fn_zipper)

          {:ok, get_fn_zipper} = Igniter.Code.Function.move_to_nth_argument(zipper, 2)
          get_fn_zipper_node = Sourceror.Zipper.node(get_fn_zipper)

          new_datasource =
            quote do
              datasource unquote(key) do
                type :selection
                list unquote(list_fn_zipper_node)
                get unquote(get_fn_zipper_node)
              end
            end

          updated_zipper = Igniter.Code.Common.replace_code(zipper, new_datasource)

          {:ok, updated_zipper}
        end
      )
    end

    defp remove_use_datasource(zipper) do
      {:ok, Igniter.Code.Common.remove_all_matches(zipper, &use_datasource?(&1))}
    end

    defp rewrite_listing_filters(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &filters?(&1),
        fn zipper ->
          node = Sourceror.Zipper.node(zipper)

          zipper =
            case node do
              {:filters, meta_filters, [args]} ->
                case args do
                  {:__block__, _meta_args_block, [keyword_list_blocks]}
                  when is_list(keyword_list_blocks) ->
                    # Transform each keyword list into a `:filter` call
                    new_filter_calls =
                      Enum.map_join(keyword_list_blocks, "\n", fn keyword_list_block ->
                        {:__block__, _meta_keyword_list, [keyword_tuples]} = keyword_list_block

                        # Reconstruct the keyword list
                        keywords =
                          Enum.map(keyword_tuples, fn
                            {{:__block__, meta_key, [key]}, value_ast} ->
                              # Reconstruct the key with its metadata
                              key_ast = {:__block__, meta_key, [key]}
                              {key_ast, value_ast}
                          end)

                        # Create a new `:filter` function call1
                        Sourceror.to_string({:filter, meta_filters, [keywords]})
                      end)

                    Igniter.Code.Common.replace_code(zipper, new_filter_calls)

                  _ ->
                    # Unexpected structure; continue traversal
                    require Logger
                    Logger.error("——————— :filters with unexpected structure")
                    zipper
                end

              _ ->
                # Not a `:filters` function call; continue traversal
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp rewrite_listing_actions(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &actions?(&1),
        fn zipper ->
          node = Sourceror.Zipper.node(zipper)

          zipper =
            case node do
              {:actions, meta_actions, [args]} ->
                case args do
                  {:__block__, _meta_args_block, [keyword_list_blocks]}
                  when is_list(keyword_list_blocks) ->
                    # Transform each keyword list into a `:action` call
                    new_action_calls =
                      Enum.map_join(keyword_list_blocks, "\n", fn keyword_list_block ->
                        {:__block__, _meta_keyword_list, [keyword_tuples]} = keyword_list_block

                        # Reconstruct the keyword list
                        keywords =
                          Enum.map(keyword_tuples, fn
                            {{:__block__, meta_key, [key]}, value_ast} ->
                              # Reconstruct the key with its metadata
                              key_ast = {:__block__, meta_key, [key]}
                              {key_ast, value_ast}
                          end)

                        # Create a new `:action` function call
                        Sourceror.to_string({:action, meta_actions, [keywords]})
                      end)

                    Igniter.Code.Common.replace_code(zipper, new_action_calls)

                  _ ->
                    # Unexpected structure; continue traversal
                    require Logger
                    Logger.error("——————— :actions with unexpected structure")
                    zipper
                end

              _ ->
                # Not a `:actions` function call; continue traversal
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp add_villain_relations(zipper, villain_fields) do
      missing_fields = Enum.reject(villain_fields, &relation_declared?(zipper, &1))

      if missing_fields != [] do
        case Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :relations,
               1
             ) do
          :error ->
            code =
              """
              relations do
                #{Enum.map_join(missing_fields, "\n", fn field -> """
                relation #{inspect(field)}, :has_many, module: :blocks
                """ end)}
              end
              """

            {:ok, Igniter.Code.Common.add_code(zipper, code)}

          {:ok, zipper} ->
            case Igniter.Code.Common.move_to_do_block(zipper) do
              {:ok, zipper} ->
                code =
                  """
                  #{Enum.map_join(missing_fields, "\n", fn field -> """
                    relation #{inspect(field)}, :has_many, module: :blocks
                    """ end)}
                  """

                {:ok, Igniter.Code.Common.add_code(zipper, code)}

              _ ->
                {:ok, zipper}
            end
        end
      else
        {:ok, zipper}
      end
    end

    defp remove_villain_attributes(zipper) do
      {:ok, Igniter.Code.Common.remove_all_matches(zipper, &villain_attribute?(&1))}
    end

    defp collect_villain_fields(zipper) do
      zipper
      |> Igniter.Code.Common.find_all(&villain_attribute?(&1))
      |> Enum.map(fn attribute_zipper ->
        attribute_zipper
        |> Sourceror.Zipper.node()
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
      |> Igniter.Code.Common.find_all(fn relation_zipper ->
        Igniter.Code.Function.function_call?(relation_zipper, :relation) and
          Igniter.Code.Function.argument_equals?(relation_zipper, 0, field)
      end)
      |> Enum.any?()
    end

    defp rewrite_meta_field(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &meta_field?(&1),
        fn zipper ->
          zipper =
            case Sourceror.Zipper.node(zipper) do
              {:meta_field, metadata, arguments} ->
                new_node = {:field, metadata, arguments}
                Sourceror.Zipper.replace(zipper, new_node)

              _ ->
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp rewrite_json_ld_field(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &json_ld_field?(&1),
        fn zipper ->
          zipper =
            case Sourceror.Zipper.node(zipper) do
              {:json_ld_field, metadata, arguments} ->
                new_node = {:field, metadata, arguments}
                Sourceror.Zipper.replace(zipper, new_node)

              _ ->
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp rewrite_listing_query(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &listing_query?(&1),
        fn zipper ->
          zipper =
            case Sourceror.Zipper.node(zipper) do
              {:listing_query, metadata, arguments} ->
                new_node = {:query, metadata, arguments}
                Sourceror.Zipper.replace(zipper, new_node)

              _ ->
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp rewrite_form_query(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &form_query?(&1),
        fn zipper ->
          zipper =
            case Sourceror.Zipper.node(zipper) do
              {:form_query, metadata, arguments} ->
                new_node = {:query, metadata, arguments}
                Sourceror.Zipper.replace(zipper, new_node)

              _ ->
                zipper
            end

          {:ok, zipper}
        end
      )
    end

    defp rewrite_slug_source(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &input_slug?(&1),
        fn zipper ->
          case Igniter.Code.Function.move_to_nth_argument(zipper, 2) do
            {:ok, zipper} ->
              keyword_list_node = Sourceror.Zipper.node(zipper)

              new_keyword_list =
                Enum.map(keyword_list_node, fn
                  # Match keyword tuples where key is wrapped in a :__block__
                  {{:__block__, meta_key, [:for]}, value_ast} ->
                    new_key_ast = {:__block__, meta_key, [:source]}
                    {new_key_ast, value_ast}

                  # Handle other possible structures (e.g., keys with metadata)
                  {{:__block__, meta_key, [:for]}, meta_value, value_ast} ->
                    new_key_ast = {:__block__, meta_key, [:source]}
                    {new_key_ast, meta_value, value_ast}

                  other ->
                    other
                end)

              zipper
              |> Sourceror.Zipper.replace(new_keyword_list)
              |> Sourceror.Zipper.up()
              |> then(&{:ok, &1})

            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp rewrite_entries_sources(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &input_entries?(&1),
        fn zipper ->
          case Igniter.Code.Function.move_to_nth_argument(zipper, 2) do
            {:ok, zipper} ->
              keyword_list_node = Sourceror.Zipper.node(zipper)

              new_keyword_list =
                Enum.map(keyword_list_node, fn
                  # Match keyword tuples where key is wrapped in a :__block__
                  {{:__block__, meta_key, [:for]}, value_ast} ->
                    new_key_ast = {:__block__, meta_key, [:sources]}
                    {new_key_ast, value_ast}

                  # Handle other possible structures (e.g., keys with metadata)
                  {{:__block__, meta_key, [:for]}, meta_value, value_ast} ->
                    new_key_ast = {:__block__, meta_key, [:sources]}
                    {new_key_ast, meta_value, value_ast}

                  other ->
                    other
                end)

              zipper
              |> Sourceror.Zipper.replace(new_keyword_list)
              |> Sourceror.Zipper.up()
              |> then(&{:ok, &1})

            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp rewrite_inputs_for(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &inputs_for_with_three_arity?(&1),
        fn zipper ->
          with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
               macros <- extract_macros(zipper),
               zipper <- Sourceror.Zipper.remove(zipper),
               {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
               zipper <- Igniter.Code.Common.add_code(zipper, macros, placement: :before) do
            fs =
              zipper
              |> Sourceror.Zipper.up()
              |> Sourceror.Zipper.up()
              |> Sourceror.Zipper.up()

            {:ok, fs}
          else
            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp rewrite_fieldsets(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &fieldset_with_two_arity?(&1),
        fn zipper ->
          with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 0),
               macros <- extract_macros(zipper),
               zipper <- Sourceror.Zipper.remove(zipper),
               {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
               zipper <- Igniter.Code.Common.add_code(zipper, macros, placement: :before) do
            fs =
              zipper
              |> Sourceror.Zipper.up()
              |> Sourceror.Zipper.up()
              |> Sourceror.Zipper.up()

            {:ok, fs}
          else
            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp rewrite_traits(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &trait_villain?(&1),
        fn zipper ->
          new_trait = "trait Brando.Trait.Blocks"
          {:ok, Igniter.Code.Common.replace_code(zipper, new_trait)}
        end
      )
    end

    defp rewrite_forms(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &forms_with_keyword_lists?(&1),
        fn zipper ->
          option_index =
            if Igniter.Code.Function.function_call?(zipper, :form, 3),
              do: 1,
              else: 0

          case Igniter.Code.Function.move_to_nth_argument(zipper, option_index) do
            {:ok, zipper} ->
              macros = extract_macros(zipper)
              zipper = Sourceror.Zipper.remove(zipper)
              {:ok, zipper} = Igniter.Code.Common.move_to_do_block(zipper)
              zipper = Igniter.Code.Common.add_code(zipper, macros, placement: :before)

              fs =
                zipper
                |> Sourceror.Zipper.up()
                |> Sourceror.Zipper.up()
                |> Sourceror.Zipper.up()

              {:ok, fs}

            :error ->
              {:ok, zipper}
          end
        end
      )
    end

    defp extract_macros(zipper) do
      zipper
      |> Sourceror.Zipper.node()
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
      Igniter.Code.Function.function_call?(zipper, :fieldset, 2)
    end

    defp inputs_for_with_three_arity?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :inputs_for, 3)
    end

    defp forms_with_keyword_lists?(zipper) do
      (Igniter.Code.Function.function_call?(zipper, :form, 2) and
         Igniter.Code.Function.argument_matches_predicate?(zipper, 0, fn argument_zipper ->
           Igniter.Code.List.list?(argument_zipper)
         end)) or
        (Igniter.Code.Function.function_call?(zipper, :form, 3) and
           Igniter.Code.Function.argument_matches_predicate?(zipper, 1, fn argument_zipper ->
             Igniter.Code.List.list?(argument_zipper)
           end))
    end

    defp input_entries?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :input, 3) &&
        Igniter.Code.Function.argument_equals?(zipper, 1, :entries) &&
        Igniter.Code.Function.argument_matches_predicate?(zipper, 2, fn argument_zipper ->
          Igniter.Code.Keyword.keyword_has_path?(argument_zipper, [:for])
        end)
    end

    defp filters?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :filters, 1)
    end

    defp actions?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :actions, 1)
    end

    defp json_ld_field?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :json_ld_field, 2) ||
        Igniter.Code.Function.function_call?(zipper, :json_ld_field, 3)
    end

    defp listing_query?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :listing_query, 1)
    end

    defp form_query?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :form_query, 1)
    end

    defp meta_field?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :meta_field, 2) ||
        Igniter.Code.Function.function_call?(zipper, :meta_field, 3)
    end

    defp input_slug?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :input, 3) &&
        Igniter.Code.Function.argument_equals?(zipper, 1, :slug) &&
        Igniter.Code.Function.argument_matches_predicate?(zipper, 2, fn argument_zipper ->
          Igniter.Code.Keyword.keyword_has_path?(argument_zipper, [:for])
        end)
    end

    defp villain_attribute?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :attribute, 2) &&
        Igniter.Code.Function.argument_equals?(zipper, 1, :villain)
    end

    defp trait_villain?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :trait) &&
        Igniter.Code.Function.argument_equals?(zipper, 0, Brando.Trait.Villain)
    end

    defp use_datasource?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :use) &&
        Igniter.Code.Function.argument_equals?(zipper, 0, Brando.Datasource)
    end

    defp uses_legacy_datasource?(zipper) do
      zipper
      |> Igniter.Code.Common.find_all(&use_datasource?(&1))
      |> Enum.any?()
    end

    defp list_datasource?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :list, 2) and
        datasource_arguments?(zipper, 2)
    end

    defp selection_datasource?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :selection, 3) and
        datasource_arguments?(zipper, 3)
    end

    defp datasource_arguments?(zipper, arity) do
      case zipper |> Sourceror.Zipper.node() |> Sourceror.get_args() do
        [key | callbacks] when length(callbacks) == arity - 1 ->
          literal_atom?(key) and Enum.all?(callbacks, &callback_ast?/1)

        _ ->
          false
      end
    end

    defp literal_atom?({:__block__, _, [value]}), do: is_atom(value)
    defp literal_atom?(value), do: is_atom(value)

    defp literal_atom!({:__block__, _, [value]}) when is_atom(value), do: value
    defp literal_atom!(value) when is_atom(value), do: value

    defp callback_ast?({:fn, _, _}), do: true
    defp callback_ast?({:&, _, _}), do: true

    defp callback_ast?({:{}, _, [_module, function, args]}) do
      literal_atom?(function) and literal_list?(args)
    end

    defp callback_ast?(_), do: false

    defp literal_list?({:__block__, _, [value]}), do: is_list(value)
    defp literal_list?(value), do: is_list(value)

    defp rewrite_preview_targets(igniter) do
      rewriting_module = Igniter.Libs.Phoenix.web_module_name(igniter, LivePreview)

      case Igniter.Project.Module.find_and_update_module(igniter, rewriting_module, fn zipper ->
             Igniter.Code.Common.update_all_matches(
               zipper,
               &preview_target_call?(&1),
               fn target_zipper ->
                 {:ok, target_zipper} = replace_layout_modules(target_zipper)
                 view_module = collect_view_module(target_zipper)
                 {:ok, target_zipper} = replace_view_templates(target_zipper, view_module)
                 remove_view_modules(target_zipper)
               end
             )
           end) do
        {:ok, igniter} -> igniter
        {:error, igniter} -> igniter
      end
    end

    defp replace_layout_modules(zipper) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &layout_module_call?(&1),
        fn zipper ->
          node = Sourceror.Zipper.node(zipper)

          case node do
            {:layout_module, _metadata, [module_arg]} ->
              new_code =
                quote do
                  layout {unquote(module_arg), :app}
                end

              # Replace code and return the updated zipper
              updated_zipper = Igniter.Code.Common.replace_code(zipper, new_code)
              {:ok, updated_zipper}

            _ ->
              # Fallback case if the node structure is unexpected
              {:ok, zipper}
          end
        end
      )
    end

    defp replace_view_templates(zipper, view_module) do
      Igniter.Code.Common.update_all_matches(
        zipper,
        &view_template_call?(&1),
        fn zipper ->
          if is_nil(view_module) do
            {:ok, zipper}
          else
            node = Sourceror.Zipper.node(zipper)

            case node do
              {:view_template, _metadata, [template_arg]} ->
                new_code =
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

                # Replace code and return the updated zipper
                updated_zipper = Igniter.Code.Common.replace_code(zipper, new_code)
                {:ok, updated_zipper}

              _ ->
                # Fallback case if the node structure is unexpected
                {:ok, zipper}
            end
          end
        end
      )
    end

    defp collect_view_module(zipper) do
      zipper
      |> Igniter.Code.Common.find_all(&view_module_call?(&1))
      |> List.first()
      |> case do
        nil -> nil
        view_module_zipper -> view_module_zipper |> Sourceror.Zipper.node() |> Sourceror.get_args() |> List.first()
      end
    end

    defp remove_view_modules(zipper) do
      # Remove all view_module calls
      Igniter.Code.Common.remove_all_matches(zipper, &view_module_call?(&1))
      |> then(&{:ok, &1})
    end

    defp layout_module_call?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :layout_module, 1)
    end

    defp view_module_call?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :view_module, 1)
    end

    defp view_template_call?(zipper) do
      # Could be `view_template "some_string"` or `view_template fn e -> e.template end`
      Igniter.Code.Function.function_call?(zipper, :view_template, 1)
    end

    defp preview_target_call?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :preview_target, 2)
    end

    defp add_notices(igniter) do
      Igniter.add_notice(igniter, """
      Brando 0.54 source migration prepared.

      Continue in this order:

        1. Review the complete Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`.
        2. Run `mix brando.upgrade` to copy missing Brando Ecto migrations.
        3. For every application Blueprint with generated migration history,
           run `mix brando.gen.blueprint_migration MyApp.Domain.Schema`.
        4. Review every generated `up/0` and `down/0`, test rollback/forward,
           and commit the source, migrations, and snapshots together.
        5. Run `mix ecto.migrate` only after that review.
        6. After the database migration, run `mix brando.entries.resave` and
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
        * Back up Gettext catalogs before attempting recovery. After extracting
          the backend and frontend catalogs, run the copied helper explicitly
          with Bash, for example:

              bash scripts/sync_gettext.sh priv/gettext/backend/no/LC_MESSAGES

          Review its diff; it only fills empty single-line translations from
          sibling `.po` files and cannot decide plural or contextual translations.
      """)
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
