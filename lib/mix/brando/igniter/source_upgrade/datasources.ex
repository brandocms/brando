if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.Datasources do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.53's `use Brando.Datasource` also did `import Ecto.Query`, which
    # datasource callbacks relied on (`from t in Member, where: …`). A
    # Blueprint whose functions call one of Ecto.Query's macros or functions
    # gets the same plain `import Ecto.Query` in the `use`'s place; an
    # `import Ecto.Query, only: […]` it already had is folded into it.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Sourceror.Zipper

    @doc """
    Removes `use Brando.Datasource` from the Blueprint in `zipper`, putting
    `import Ecto.Query` in its place when the module uses Ecto.Query and does
    not import all of it already.
    """
    def remove_use(zipper, use_datasource?) do
      ast = zipper |> Zipper.topmost() |> Zipper.node()

      if not uses_ecto_query?(ast) or plain_import?(ast) do
        {:ok, Common.remove_all_matches(zipper, use_datasource?)}
      else
        zipper
        |> Common.remove_all_matches(&partial_import?/1)
        |> Zipper.topmost()
        |> Common.update_all_matches(use_datasource?, &{:ok, Common.replace_code(&1, "import Ecto.Query")})
      end
    end

    defp uses_ecto_query?(ast) do
      names = query_names() -- defined_names(ast)

      ast
      |> function_bodies()
      |> Enum.any?(fn body ->
        {_body, found} =
          Macro.prewalk(body, false, fn
            {name, _, args} = node, found when is_atom(name) and is_list(args) -> {node, found or name in names}
            node, found -> {node, found}
          end)

        found
      end)
    end

    # Everything `import Ecto.Query` brings in.
    defp query_names do
      Code.ensure_loaded(Ecto.Query)

      (Ecto.Query.__info__(:macros) ++ Ecto.Query.__info__(:functions))
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&(&1 |> to_string() |> String.starts_with?("__")))
      |> Enum.uniq()
    end

    defp function_bodies(ast) do
      {_ast, bodies} =
        Macro.prewalk(ast, [], fn
          {kind, _, [_head, body]} = node, bodies when kind in [:def, :defp] -> {node, [body | bodies]}
          {:fn, _, clauses} = node, bodies -> {node, [clauses | bodies]}
          node, bodies -> {node, bodies}
        end)

      bodies
    end

    defp defined_names(ast) do
      {_ast, names} =
        Macro.prewalk(ast, [], fn
          {kind, _, [{:when, _, [{name, _, _} | _]} | _]} = node, names when kind in [:def, :defp] ->
            {node, [name | names]}

          {kind, _, [{name, _, _} | _]} = node, names when kind in [:def, :defp] ->
            {node, [name | names]}

          node, names ->
            {node, names}
        end)

      names
    end

    defp plain_import?(ast) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:import, _, [{:__aliases__, _, [:Ecto, :Query]}]} = node, _found -> {node, true}
          node, found -> {node, found}
        end)

      found
    end

    defp partial_import?(zipper) do
      CodeFunction.function_call?(zipper, :import, 2) and CodeFunction.argument_equals?(zipper, 0, Ecto.Query)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.Datasources do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
