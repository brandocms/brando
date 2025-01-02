defmodule Mix.Tasks.Brando.Migrate54 do
  use Igniter.Mix.Task

  @shortdoc "Migrates some code to Brando 0.54"
  @moduledoc """
  #{@shortdoc}
  """

  def info(_argv, _source) do
    %Igniter.Mix.Task.Info{group: :brando}
  end

  def igniter(igniter, _argv) do
    Agent.start_link(fn -> %{} end, name: :villains)

    {igniter, modules} = find_blueprints(igniter)

    igniter =
      modules
      |> Enum.reduce(igniter, fn module, igniter ->
        igniter
        |> rewrite_list_datasources(module)
        |> rewrite_selection_datasources(module)
        |> remove_use_datasource(module)
        |> rewrite_fieldsets(module)
        |> rewrite_inputs_for(module)
        |> rewrite_forms(module)
        |> rewrite_listing_filters(module)
        |> rewrite_listing_actions(module)
        |> rewrite_listing_query(module)
        |> rewrite_form_query(module)
        |> rewrite_entries_sources(module)
        |> rewrite_slug_source(module)
        |> rewrite_json_ld_field(module)
        |> rewrite_meta_field(module)
        |> rewrite_villain(module)
        |> add_villain_relations(module)
      end)

    igniter
    |> rewrite_preview_targets()
    |> copy_gettext_script()
    |> copy_updated_migration_script()
    |> Igniter.add_task("igniter.update_gettext")
    |> add_notices()
    |> add_warnings()
  end

  defp remove_use_datasource(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
      {:ok, Igniter.Code.Common.remove_all_matches(zipper, &use_datasource?(&1))}
    end)
  end

  defp rewrite_list_datasources(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
  end

  defp rewrite_selection_datasources(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
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

  def rewrite_listing_filters(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
                      keyword_list_blocks
                      |> Enum.map(fn keyword_list_block ->
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
                      |> Enum.join("\n")

                    Igniter.Code.Common.replace_code(zipper, new_filter_calls)

                  _ ->
                    # Unexpected structure; continue traversal
                    IO.inspect("——————— :filters with unexpected structure")
                    zipper
                end

              _ ->
                # Not a `:filters` function call; continue traversal
                zipper
            end

          {:ok, zipper}
        end
      )
    end)
  end

  def rewrite_listing_actions(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
                      Enum.map(keyword_list_blocks, fn keyword_list_block ->
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
                        {:action, meta_actions, [keywords]}
                        |> Sourceror.to_string()
                      end)
                      |> Enum.join("\n")

                    Igniter.Code.Common.replace_code(zipper, new_action_calls)

                  _ ->
                    # Unexpected structure; continue traversal
                    IO.inspect("——————— :actions with unexpected structure")
                    zipper
                end

              _ ->
                # Not a `:actions` function call; continue traversal
                zipper
            end

          {:ok, zipper}
        end
      )
    end)
  end

  defp add_villain_relations(igniter, rewriting_module) do
    villains_for_this_module =
      Agent.get(:villains, fn state ->
        Map.get(state, rewriting_module, [])
      end)

    if villains_for_this_module != [] do
      Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
        case Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :relations,
               1
             ) do
          :error ->
            code =
              """
              relations do
                #{Enum.map(villains_for_this_module, fn villain -> """
                relation #{inspect(villain)}, :has_many, module: :blocks
                """ end) |> Enum.join("\n")}
              end
              """

            {:ok, Igniter.Code.Common.add_code(zipper, code)}

          {:ok, zipper} ->
            with {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper) do
              code =
                """
                #{Enum.map(villains_for_this_module, fn villain -> """
                  relation #{inspect(villain)}, :has_many, module: :blocks
                  """ end) |> Enum.join("\n")}
                """

              {:ok, Igniter.Code.Common.add_code(zipper, code)}
            else
              _ ->
                {:ok, zipper}
            end
        end
      end)
    else
      igniter
    end
  end

  defp rewrite_villain(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
      {:ok, zipper} =
        Igniter.Code.Common.update_all_matches(
          zipper,
          &villain_attribute?(&1),
          fn zipper ->
            node = Sourceror.Zipper.node(zipper)
            {:attribute, _, [{:__block__, _, [key]}, _]} = node
            string_key = to_string(key)

            fixed_key =
              string_key
              |> String.replace("_data", "_blocks")
              |> String.replace("data", "blocks")
              |> String.to_atom()

            Agent.update(:villains, fn state ->
              Map.update(state, rewriting_module, [fixed_key], fn villains ->
                [fixed_key | villains]
              end)
            end)

            {:ok, zipper}
          end
        )

      {:ok, Igniter.Code.Common.remove_all_matches(zipper, &villain_attribute?(&1))}
    end)
  end

  defp rewrite_meta_field(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
  end

  defp rewrite_json_ld_field(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
  end

  defp rewrite_listing_query(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
  end

  defp rewrite_form_query(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
  end

  defp rewrite_slug_source(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
      Igniter.Code.Common.update_all_matches(
        zipper,
        &input_slug?(&1),
        fn zipper ->
          with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 2) do
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
          else
            :error ->
              {:ok, zipper}
          end
        end
      )
    end)
  end

  defp rewrite_entries_sources(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
      Igniter.Code.Common.update_all_matches(
        zipper,
        &input_entries?(&1),
        fn zipper ->
          with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 2) do
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
          else
            :error ->
              {:ok, zipper}
          end
        end
      )
    end)
  end

  defp rewrite_inputs_for(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
  end

  defp rewrite_fieldsets(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
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
    end)
  end

  defp rewrite_forms(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
      Igniter.Code.Common.update_all_matches(
        zipper,
        &forms_with_keyword_lists?(&1),
        fn zipper ->
          with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 0) do
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
          else
            :error ->
              {:ok, zipper}
          end
        end
      )
    end)
  end

  defp extract_macros(zipper) do
    {_zipper, acc} =
      Sourceror.Zipper.traverse(zipper, [], fn z, acc ->
        case Sourceror.Zipper.node(z) do
          {{:__block__, _, [key]}, {:__block__, _, [value]}}
          when is_atom(key) and is_atom(value) ->
            {z, acc ++ ["#{key} #{inspect(value)}"]}

          {{:__block__, _, [key]}, value}
          when is_atom(key) ->
            v = Sourceror.to_string(value)
            {z, acc ++ ["#{key} #{v}"]}

          _ ->
            {z, acc}
        end
      end)

    Enum.join(acc, "\r\n")
  end

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

  defp use_datasource?(zipper) do
    Igniter.Code.Function.function_call?(zipper, :use) &&
      Igniter.Code.Function.argument_equals?(zipper, 0, Brando.Datasource)
  end

  defp list_datasource?(zipper) do
    Igniter.Code.Function.function_call?(zipper, :list, 2)
  end

  defp selection_datasource?(zipper) do
    Igniter.Code.Function.function_call?(zipper, :selection, 3)
  end

  defp preview_target?(zipper) do
    Igniter.Code.Function.function_call?(zipper, :preview_target, 2)
  end

  defp add_notices(igniter) do
    igniter
  end

  defp add_warnings(igniter) do
    igniter
    |> Igniter.add_warning("""
    Go through your blueprints and ensure that you set

        persist_identifier false

    to all modules you don't want to persist the identifier for.
    Then you must resave your entries to ensure we render block fields correctly:

        mix brando.entries.resave

    Finally sync identifiers for all entries:

        mix brando.identifiers.sync

    You must also update your gettext files. There is a new script in your scripts/ folder
    called sync_gettext.sh that you can run to try to update your gettext files from the old format.

    First extract your translations:

      mix gettext.extract --merge priv/gettext/backend --locale no --plural-forms-header "nplurals=2; plural=(n != 1)";
      mix gettext.extract --merge priv/gettext/frontend --locale no --plural-forms-header "nplurals=2; plural=(n != 1)";

    Then run the script

      ./scripts/sync_gettext.sh priv/gettext/no/LC_MESSAGES

    """)
  end

  defp rewrite_preview_targets(igniter) do
    rewriting_module = Igniter.Libs.Phoenix.web_module_name(igniter, LivePreview)

    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
      # We only match on calls to preview_target/1
      Igniter.Code.Common.update_all_matches(
        zipper,
        &preview_target?(&1),
        fn zipper ->
          # Move into the `do` block of `preview_target do ... end`
          with {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper) do
            # We’ll gather calls for layout, view_module, and view_template,
            # remove them from code, and then re-inject them in the new format.
            #
            {zipper, layout_call} = extract_and_remove_layout_module(zipper)
            {zipper, view_module_call} = extract_and_remove_view_module(zipper)
            {zipper, view_template_call} = extract_and_remove_view_template(zipper)

            # Build the new lines
            new_lines =
              build_new_layout_call(layout_call) <>
                build_new_template_call(view_module_call, view_template_call)

            # Insert them at the end (or beginning) of the do-block
            updated_zipper = Igniter.Code.Common.add_code(zipper, new_lines, placement: :before)

            {:ok, updated_zipper}
          else
            :error ->
              # If we can't move to the do block for some reason, just carry on.
              {:ok, zipper}
          end
        end
      )
    end)
  end

  defp extract_and_remove_layout_module(zipper) do
    extract_and_remove_first_match(
      zipper,
      &layout_module_call?/1
    )
  end

  defp extract_and_remove_view_module(zipper) do
    extract_and_remove_first_match(
      zipper,
      &view_module_call?/1
    )
  end

  defp extract_and_remove_view_template(zipper) do
    extract_and_remove_first_match(
      zipper,
      &view_template_call?/1
    )
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

  defp build_new_layout_call(nil), do: ""

  defp build_new_layout_call(ast) do
    case Sourceror.get_args(ast) do
      [module_ast] ->
        module_str = Sourceror.to_string(module_ast)

        """
        layout {#{module_str}, "app"}
        """

      _ ->
        ""
    end
  end

  #    Combining view_module + view_template:
  #    - if view_template is a function: template fn e -> {<view_module>, e.template} end
  #    - if view_template is a string:  template {<view_module>, "some_string"}
  # No view_module, skip
  defp build_new_template_call(nil, _), do: ""
  # No view_template, skip
  defp build_new_template_call(_, nil), do: ""

  defp build_new_template_call(view_module_ast, view_template_ast) do
    [view_module] = Sourceror.get_args(view_module_ast)

    template_args = Sourceror.get_args(view_template_ast)
    [maybe_function] = template_args

    cond do
      # Handle a function: e.g. fn e -> e.template end
      function_ast?(maybe_function) ->
        """
        template fn e -> {#{Sourceror.to_string(view_module)}, e.template} end
        """

      # Otherwise treat it as a string or whatever literal is there
      true ->
        """
        template {#{Sourceror.to_string(view_module)}, #{Sourceror.to_string(maybe_function)}}
        """
    end
  end

  # 6) A small helper to see if the AST is a function literal.
  defp function_ast?({:fn, _, _}), do: true
  defp function_ast?(_), do: false

  @doc """
  Traverse the zipper until the first node matching `predicate` is found.
  When found, call `update_fn` on that node to return a modified zipper.
  Halts traversal immediately after the first match/update.

  Returns the updated zipper, or the original zipper if no match is found.
  """
  def update_first_match(zipper, predicate, update_fn) do
    # We’ll rely on Zipper.traverse_while/3 with a :cont / :halt approach.
    Sourceror.Zipper.traverse_while(zipper, fn z ->
      if predicate.(z) do
        case update_fn.(z) do
          {:ok, new_z} ->
            # Stop traversal and return the newly updated zipper
            {:halt, new_z}

          :error ->
            # You can decide how to handle an :error from update_fn
            {:halt, z}
        end
      else
        :cont
      end
    end)
  end

  @doc """
  Finds the first node that matches `predicate`, returns that node’s AST, and removes
  it from the zipper. If none is found, returns `{zipper, nil}`.
  """
  def extract_and_remove_first_match(zipper, predicate) do
    # We use an accumulator to store our matched node.
    {final_zipper, matched_node} =
      Sourceror.Zipper.traverse_while(zipper, nil, fn z, _acc ->
        if predicate.(z) do
          node = Sourceror.Zipper.node(z)
          # Remove the matched node
          new_z = Sourceror.Zipper.remove(z)
          # Stop traversal, returning `new_z` as updated zipper, and `node` as the accumulator
          {:halt, new_z, node}
        else
          # Keep traversing
          {:cont, z, nil}
        end
      end)

    {final_zipper, matched_node}
  end
end
