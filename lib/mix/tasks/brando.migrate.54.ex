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
        |> rewrite_fieldsets(module)
        |> rewrite_inputs_for(module)
        |> rewrite_forms(module)
        |> rewrite_listings(module)
        |> rewrite_listing_filters(module)
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
    |> add_notices()
    |> add_warnings()
  end

  def rewrite_listings(igniter, rewriting_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, rewriting_module, fn zipper ->
      Igniter.Code.Common.update_all_matches(
        zipper,
        &listing?(&1),
        fn zipper ->
          {:listing, listing_meta, [args]} = Sourceror.Zipper.node(zipper)
          [{{:__block__, do_meta, [:do]}, {:__block__, block_meta, block_body}}] = args

          new_block_body = process_block_body(block_body)

          # Reconstruct the block with the new block_body
          new_block = {{:__block__, do_meta, [:do]}, {:__block__, block_meta, new_block_body}}

          # Reconstruct the :listing node
          new_node = {:listing, listing_meta, [new_block]}

          # Replace the node in the zipper
          Sourceror.Zipper.replace(zipper, new_node)
          {:ok, zipper}
        end
      )
    end)
  end

  defp process_block_body(block_body) do
    Enum.flat_map(block_body, fn expr ->
      case expr do
        {:filters, filters_meta, [filters_args]} ->
          # Transform the filters_args into multiple filter calls
          create_filter_calls(filters_args, filters_meta)

        _ ->
          # Keep the expression unchanged
          [expr]
      end
    end)
  end

  defp create_filter_calls(filters_args, filters_meta) do
    # filters_args is a {:__block__, _, filters_list}
    case filters_args do
      {:__block__, _, filters_list} when is_list(filters_list) ->
        # filters_list is a list of filter blocks
        Enum.map(filters_list, fn filter_block ->
          # Each filter_block is a {:__block__, _, [[filter_keywords]]}
          {:__block__, _, [filter_keywords_list]} = filter_block

          # filter_keywords_list is a list containing filter_keywords
          [filter_keywords] = filter_keywords_list

          # Now filter_keywords is a list of keyword tuples
          # Create the :filter call
          {:filter, filters_meta, [filter_keywords]}
        end)

      _ ->
        # Unexpected structure; return the original filters call
        [{:filters, filters_meta, [filters_args]}]
    end
  end

  def rewrite_listing_filters(igniter, rewriting_module) do
    # filters([
    #   [label: gettext("Title"), filter: "title"],
    #   [label: gettext("Category"), filter: "category"]
    # ])

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

                        # Create a new `:filter` function call
                        {:filter, meta_filters, [keywords]} |> Sourceror.to_string()
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

          zipper = Sourceror.Zipper.remove(zipper)

          {:ok, zipper}
        end
      )
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
               zipper <- Igniter.Code.Common.add_code(zipper, macros, :before) do
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
               zipper <- Igniter.Code.Common.add_code(zipper, macros, :before) do
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
            zipper = Igniter.Code.Common.add_code(zipper, macros, :before)

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

  defp listing?(zipper) do
    Igniter.Code.Function.function_call?(zipper, :listing, 1) ||
      Igniter.Code.Function.function_call?(zipper, :listing, 2)
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

  defp add_notices(igniter) do
    igniter
  end

  defp add_warnings(igniter) do
    Igniter.add_warning(igniter, """
    Go through your blueprints and ensure that you set

        persist_identifier false

    to all modules you don't want to persist the identifier for.
    Then you must resave your entries to ensure we render block fields correctly:

        mix brando.entries.resave

    Finally sync identifiers for all entries:

        mix brando.identifiers.sync


    """)
  end
end
