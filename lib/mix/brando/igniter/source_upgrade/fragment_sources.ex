if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.FragmentSources do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Where an application module holds fragments maps, read from its AST:
    #
    #   * the variables a function binds once, to what `get_fragments` returns
    #     (`{:ok, parts} = Pages.get_fragments(opts)`); a variable the function
    #     binds again, as a `fn` parameter, say, could be anything there;
    #   * the assigns it sets (`assign/2,3`, `assign_new/3`, `render/3`), and
    #     whether each is set from such a variable.
    #
    # Anything it cannot read counts as other data, so the reads are listed,
    # not rewritten.

    @assign_calls [:assign, :assign_new, :render]
    @scopes [:def, :defp]

    @doc """
    `%{bindings: [{variable, first_line, last_line}], sites: [{assign, from_fragments?}]}`
    for an `.ex` file; nothing for other files, which bind no variables.
    """
    def analyze(path, content) do
      with ".ex" <- Path.extname(path),
           {:ok, ast} <- Sourceror.parse_string(content) do
        functions = functions(ast)
        bindings = Enum.flat_map(functions, &fragment_bindings/1)
        %{bindings: bindings, sites: assign_sites(ast, bindings)}
      else
        _ -> %{bindings: [], sites: []}
      end
    end

    @doc "Whether `variable` holds fragments at `line`."
    def bound?(bindings, variable, line),
      do: Enum.any?(bindings, fn {name, first, last} -> name == variable and line in first..last//1 end)

    defp functions(ast) do
      ast
      |> Macro.prewalk([], fn
        {kind, _meta, [_head | _]} = node, functions when kind in @scopes ->
          %{start: start, end: finish} = Sourceror.get_range(node)
          {node, [{node, start[:line], finish[:line]} | functions]}

        node, functions ->
          {node, functions}
      end)
      |> elem(1)
    end

    # The variables bound to `get_fragments` that the function binds nowhere else.
    defp fragment_bindings({function, first, last}) do
      counts = function |> bound_variables() |> Enum.frequencies()

      for {:fragments, variable} <- function |> matches() |> Enum.map(&fragments_match/1),
          Map.get(counts, variable) == 1,
          uniq: true,
          do: {Atom.to_string(variable), first, last}
    end

    defp matches(function) do
      function
      |> Macro.prewalk([], fn
        {op, _, [_left, _right]} = node, matches when op in [:=, :<-] -> {node, [node | matches]}
        node, matches -> {node, matches}
      end)
      |> elem(1)
    end

    defp fragments_match({_op, _, [left, right]}) do
      with true <- get_fragments_call?(right),
           variable when is_atom(variable) <- fragments_pattern(left) do
        {:fragments, variable}
      else
        _ -> nil
      end
    end

    defp fragments_pattern({:__block__, _, [{ok, {variable, _, context}}]}) when is_atom(context) do
      if unwrap(ok) == :ok, do: variable
    end

    defp fragments_pattern({variable, _, context}) when is_atom(variable) and is_atom(context), do: variable
    defp fragments_pattern(_pattern), do: nil

    defp get_fragments_call?(ast) do
      ast
      |> Macro.prewalk(false, fn
        {:get_fragments, _, args} = node, _found when is_list(args) -> {node, true}
        {{:., _, [_module, :get_fragments]}, _, _args} = node, _found -> {node, true}
        node, found -> {node, found}
      end)
      |> elem(1)
    end

    # Every variable the function binds: in its head, on the left of `=` and
    # `<-`, and in the heads of `fn`, `case` and `with` clauses.
    defp bound_variables({_kind, _meta, [head | _body]} = function) do
      patterns =
        function
        |> Macro.prewalk([], fn
          {op, _, [left, _right]} = node, patterns when op in [:=, :<-] -> {node, [left | patterns]}
          {:->, _, [heads, _body]} = node, patterns -> {node, heads ++ patterns}
          node, patterns -> {node, patterns}
        end)
        |> elem(1)

      Enum.flat_map([head | patterns], &pattern_variables/1)
    end

    defp pattern_variables(pattern) do
      pattern
      |> Macro.prewalk([], fn
        {:^, _, _} = _pinned, variables -> {nil, variables}
        {name, _, context} = node, variables when is_atom(name) and is_atom(context) -> {node, [name | variables]}
        node, variables -> {node, variables}
      end)
      |> elem(1)
      |> Enum.reject(&(&1 |> Atom.to_string() |> String.starts_with?("_")))
    end

    # `{assign, from_fragments?}` for each assign the module sets.
    defp assign_sites(ast, bindings) do
      ast
      |> Macro.prewalk([], fn node, sites -> {node, assign_call_sites(node, bindings) ++ sites} end)
      |> elem(1)
    end

    defp assign_call_sites({name, meta, args} = _call, bindings) when name in @assign_calls and is_list(args),
      do: call_sites(name, args, meta[:line], bindings)

    defp assign_call_sites({{:., _, [_module, name]}, meta, args}, bindings) when name in @assign_calls and is_list(args),
      do: call_sites(name, args, meta[:line], bindings)

    defp assign_call_sites(_node, _bindings), do: []

    # `assign(conn, :key, value)`, piped `assign(:key, value)`, a keyword list
    # or map of assigns, and `render(conn, template, assigns)`.
    defp call_sites(name, args, line, bindings) do
      case {name, Enum.map(args, &unwrap/1)} do
        {:render, args} -> args |> List.last() |> pairs() |> sites(line, bindings)
        {_name, [_conn, key, value]} when is_atom(key) -> sites([{key, value}], line, bindings)
        {_name, [key, value]} when is_atom(key) -> sites([{key, value}], line, bindings)
        {_name, args} -> args |> List.last() |> pairs() |> sites(line, bindings)
      end
    end

    defp sites(pairs, line, bindings) do
      for {key, value} <- pairs, is_atom(key) and not is_nil(key) do
        {Atom.to_string(key), fragments_variable?(value, line, bindings)}
      end
    end

    defp fragments_variable?({variable, _, context}, line, bindings) when is_atom(variable) and is_atom(context),
      do: bound?(bindings, Atom.to_string(variable), line)

    defp fragments_variable?(_value, _line, _bindings), do: false

    defp pairs({:%{}, _, pairs}), do: Enum.map(pairs, fn {key, value} -> {unwrap(key), value} end)
    defp pairs(list) when is_list(list), do: for({key, value} <- list, do: {unwrap(key), value})
    defp pairs(_value), do: []

    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.FragmentSources do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
