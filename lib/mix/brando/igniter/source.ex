if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Source do
    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Project.Module, as: ProjectModule

    def ensure_import(igniter, module, imported, only) do
      ProjectModule.find_and_update_module!(igniter, module, &update_import(&1, imported, only))
    end

    defp update_import(zipper, imported, only) do
      case find_call(zipper, :import, [1, 2], imported) do
        :error ->
          {:ok, Common.add_code(zipper, "import #{inspect(imported)}, only: #{inspect(only)}", placement: :before)}

        {:ok, call} ->
          update_import_options(call, imported, only)
      end
    end

    defp update_import_options(call, imported, only) do
      case CodeFunction.move_to_nth_argument(call, 1) do
        :error ->
          {:ok, call}

        {:ok, options} ->
          case Common.expand_literal(options) do
            {:ok, configured} when is_list(configured) -> merge_imports(options, configured, imported, only)
            _ -> {:error, "Expected literal options for import #{inspect(imported)}."}
          end
      end
    end

    defp merge_imports(options, configured, imported, only) do
      cond do
        Keyword.has_key?(configured, :except) ->
          {:error, "Review import #{inspect(imported)} restrictions; generated queries need #{inspect(only)}."}

        is_list(configured[:only]) ->
          merged = Enum.uniq(configured[:only] ++ only)
          CodeKeyword.set_keyword_key(options, :only, merged, &{:ok, Common.replace_code(&1, inspect(merged))})

        not Keyword.has_key?(configured, :only) ->
          {:ok, options}

        true ->
          {:error, "Expected a literal list of imported #{inspect(imported)} functions."}
      end
    end

    def ensure_call(igniter, module, name, arities, first_arg, code, options \\ []) do
      ProjectModule.find_and_update_module!(igniter, module, fn zipper ->
        case find_call(zipper, name, arities, first_arg) do
          {:ok, _} -> {:ok, zipper}
          :error -> insert(zipper, code, options)
        end
      end)
    end

    def find_call(zipper, name, arities, first_arg) do
      CodeFunction.move_to_function_call_in_current_scope(zipper, name, arities, fn call ->
        CodeFunction.argument_equals?(call, 0, first_arg)
      end)
    end

    defp insert(zipper, code, options) do
      case options[:before] do
        nil ->
          {:ok, Common.add_code(zipper, code, placement: options[:placement] || :after)}

        {name, arities, first_arg} ->
          case find_call(zipper, name, arities, first_arg) do
            {:ok, anchor} -> {:ok, Common.add_code(anchor, code, placement: :before)}
            :error -> {:error, "Could not locate #{name} #{inspect(first_arg)} to insert #{code}."}
          end
      end
    end
  end
end
