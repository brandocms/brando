if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Resource.Context do
    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Source

    def plan(igniter, metadata) do
      context = metadata.context

      igniter =
        case ProjectModule.find_module(igniter, context) do
          {:ok, {igniter, _, _}} ->
            igniter

          {:error, igniter} ->
            Files.create(igniter, "lib/#{Macro.underscore(context)}.ex", "defmodule #{inspect(context)} do\nend\n")
        end

      igniter =
        igniter
        |> Source.ensure_call(context, :use, [1, 2], Brando.Query, "use Brando.Query", placement: :before)
        |> Source.ensure_import(context, Ecto.Query, from: 2, where: 3, limit: 2)

      Enum.reduce(declarations(metadata), igniter, fn declaration, igniter ->
        ProjectModule.find_and_update_module!(igniter, context, &ensure_declaration(&1, declaration, context))
      end)
    end

    defp ensure_declaration(zipper, {macro, args, code, function}, context) do
      case CodeFunction.move_to_function_call_in_current_scope(zipper, macro, [2, 3], &arguments_match?(&1, args)) do
        {:ok, _} ->
          {:ok, zipper}

        :error ->
          if function && CodeFunction.move_to_def(zipper, function, :any) != :error do
            {:error,
             "#{inspect(context)}.#{function} already exists. Integrate the resource query explicitly to preserve the custom function."}
          else
            {:ok, Common.add_code(zipper, code)}
          end
      end
    end

    defp arguments_match?(call, args) do
      args |> Enum.with_index() |> Enum.all?(fn {value, index} -> CodeFunction.argument_equals?(call, index, value) end)
    end

    defp declarations(m) do
      schema = inspect(m.schema)
      field = m.main_field

      filter =
        if m.text_field?,
          do: "ilike(q.#{field}, ^(\"%\" <> Brando.Query.sanitize_ilike_pattern(value) <> \"%\"))",
          else: "q.#{field} == ^value"

      matches = Enum.uniq([:id, field] ++ if(:slug in m.schema.__schema__(:fields), do: [:slug], else: []))
      match_clauses = Enum.map_join(matches, "\n", &"{:#{&1}, value}, query -> from q in query, where: q.#{&1} == ^value")

      mutations =
        Enum.map([:create, :update, :delete], fn op ->
          {:mutation, [op, m.schema], "mutation :#{op}, #{schema}", String.to_atom("#{op}_#{m.naming.singular}")}
        end)

      mutations ++
        [
          {:query, [:list, m.schema], "query :list, #{schema}, do: fn query -> query end",
           String.to_atom("list_#{m.naming.plural}")},
          {:query, [:single, m.schema], "query :single, #{schema}, do: fn query -> query end",
           String.to_atom("get_#{m.naming.singular}")},
          {:filters, [m.schema],
           "filters #{schema} do\n fn {:#{field}, value}, query -> from q in query, where: #{filter} end\nend", nil},
          {:matches, [m.schema], "matches #{schema} do\n fn\n #{match_clauses}\n end\nend", nil}
        ]
    end
  end
end
