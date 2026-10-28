defmodule Brando.Credo.Check.TestCacheRestore do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["test/**/*_test.exs"]},
      restore_helpers: [:preserve_cache, :preserve_query_cache]
    ],
    explanations: [
      check: """
      A test that writes a shared cache puts it back when it exits.

      Cachex caches outlive the test's database sandbox. A value a test leaves
      in `Brando.Cache` (identity, SEO, globals, navigation, a memoised key),
      or a cleared `Cachex` cache refilled from the test's rolled-back rows,
      is read by whichever test runs next, so a later test passes or fails by
      the order the suite runs in.

      Snapshot the entry in `setup` and write it back in `on_exit`, or call
      `preserve_cache/1` (or `preserve_query_cache/1` for a schema's query
      cache entries) from `Brando.Test.Support`:

          setup do
            preserve_cache([:identity, :seo])
          end

      This check sees direct writes in the test module: `Cachex.clear/1`,
      `Brando.Cache.put/update/reload_all`, and `set/update/put` on the
      `Brando.Cache.*` modules. Removing a single key (`del`, `evict`) is not
      flagged where the test makes it. A module passes once it calls a restore
      helper, or has an `on_exit` that writes a value back (directly or through
      one of its own functions). Writes made inside the code under test (a
      context function that refreshes the identity cache) are not visible to
      it; restore those too.

      Removing a key in `on_exit` is not a restore: it leaves empty a key the
      test may have found filled (identity, SEO, globals, navigation are
      filled at boot), and the next test to read it has to refill it, which a
      test without a database connection of its own cannot do. An `on_exit`
      whose only cache writes are `del`, `evict` or `Cachex.expire` is
      flagged. Deleting a key as part of a snapshot restore, in the branch for
      a key that was empty before, is fine: the same `on_exit` writes the
      value back in the other.
      """,
      params: [
        restore_helpers: "Function names that register a cache restore themselves."
      ]
    ]

  alias Brando.Credo.Aliases
  alias Credo.SourceFile

  # Writes flagged outside `on_exit`: they leave a value behind, or clear a
  # whole cache. Removing one key (`del`, `evict`) is not flagged, since a
  # test may remove what it put there.
  @cachex_flagged ~w(clear clear!)a
  @brando_cache_flagged ~w(put update reload_all)a
  @brando_cache_module_flagged ~w(set update put)a

  # In `on_exit`, these count as a restore
  @cachex_restores ~w(clear clear! put put! put_many put_many! update update! reset reset! incr incr! decr decr! import import!)a
  @brando_cache_restores ~w(put update reload_all)a
  @brando_cache_module_restores ~w(set update put)a

  # and these do not: an emptied key the test found filled stays empty
  @cachex_removals ~w(del del! take take! expire expire!)a
  @brando_cache_removals ~w(del)a
  @brando_cache_module_removals ~w(evict evict_schema evict_entry)a

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    ast = SourceFile.ast(source_file)
    aliases = Aliases.collect(ast)
    helpers = Params.get(params, :restore_helpers, __MODULE__)
    exits = ast |> on_exits() |> Enum.map(&{&1, exit_writes(&1, ast, aliases)})
    removing_exits = for {exit, kinds} <- exits, kinds == MapSet.new([:removal]), do: exit

    writes =
      if calls_helper?(ast, helpers) or Enum.any?(exits, fn {_exit, kinds} -> :restore in kinds end),
        do: [],
        else: flagged_writes(ast, aliases)

    Enum.map(writes, &issue_for(ctx, &1)) ++ Enum.map(removing_exits, &removal_issue_for(ctx, &1))
  end

  # Writes outside `on_exit` bodies, in source order
  defp flagged_writes(ast, aliases) do
    {_ast, writes} =
      Macro.prewalk(ast, [], fn node, acc ->
        cond do
          on_exit(node) -> {nil, acc}
          write = flagged_write(node, aliases) -> {node, [write | acc]}
          true -> {node, acc}
        end
      end)

    Enum.reverse(writes)
  end

  defp on_exits(ast) do
    {_ast, exits} =
      Macro.prewalk(ast, [], fn node, acc ->
        case on_exit(node) do
          nil -> {node, acc}
          exit -> {node, [exit | acc]}
        end
      end)

    Enum.reverse(exits)
  end

  # `on_exit` or `ExUnit.Callbacks.on_exit`, as `{:on_exit, meta, args}`
  defp on_exit({:on_exit, meta, args}) when is_list(args), do: {:on_exit, meta, args}

  defp on_exit({{:., _, [{:__aliases__, _, [:ExUnit, :Callbacks]}, :on_exit]}, meta, args}) when is_list(args),
    do: {:on_exit, meta, args}

  defp on_exit(_node), do: nil

  defp flagged_write(node, aliases) do
    case cache_write(node, aliases) do
      %{flagged?: true} = write -> write
      _other -> nil
    end
  end

  # The kinds of cache write (`:restore`, `:removal`) an `on_exit` makes,
  # directly or through the module's own functions
  defp exit_writes({:on_exit, _, body}, ast, aliases) do
    functions = functions(ast, aliases)
    reached = reach(local_calls(body), functions, MapSet.new())

    Enum.reduce(reached, write_kinds(body, aliases), fn name, kinds ->
      MapSet.union(kinds, functions[name].writes)
    end)
  end

  defp reach([], _functions, seen), do: seen

  defp reach([name | rest], functions, seen) do
    case functions do
      %{^name => function} ->
        if name in seen,
          do: reach(rest, functions, seen),
          else: reach(function.calls ++ rest, functions, MapSet.put(seen, name))

      _not_local ->
        reach(rest, functions, seen)
    end
  end

  defp calls_helper?(ast, helpers) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {name, _, args} = node, acc when is_atom(name) and is_list(args) -> {node, acc or name in helpers}
        node, acc -> {node, acc}
      end)

    found?
  end

  # The module's own functions by name, all clauses together: the kinds of
  # cache write each makes and the local functions it calls
  defp functions(ast, aliases) do
    {_ast, functions} =
      Macro.prewalk(ast, %{}, fn
        {kind, _, [head | body]} = node, acc when kind in [:def, :defp] ->
          function = %{writes: write_kinds(body, aliases), calls: local_calls(body)}

          {node,
           Map.update(acc, function_name(head), function, fn existing ->
             %{writes: MapSet.union(existing.writes, function.writes), calls: existing.calls ++ function.calls}
           end)}

        node, acc ->
          {node, acc}
      end)

    functions
  end

  defp function_name({:when, _, [head | _]}), do: function_name(head)
  defp function_name({name, _, _}), do: name

  defp local_calls(ast) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {:&, _, [{:/, _, [{name, _, context}, _arity]}]} = node, acc when is_atom(name) and is_atom(context) ->
          {node, [name | acc]}

        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp write_kinds(ast, aliases) do
    {_ast, kinds} =
      Macro.prewalk(ast, MapSet.new(), fn node, acc ->
        case cache_write(node, aliases) do
          %{kind: kind} when kind != nil -> {node, MapSet.put(acc, kind)}
          _other -> {node, acc}
        end
      end)

    kinds
  end

  defp cache_write({{:., _, [{:__aliases__, meta, parts}, fun]}, _, args}, aliases) when is_list(args) do
    module = Aliases.expand(parts, aliases)
    flagged? = flagged?(module, fun)
    kind = kind(module, fun)

    if flagged? or kind do
      %{
        module: Enum.join(module, "."),
        trigger: Enum.join(parts, ".") <> ".#{fun}",
        fun: fun,
        flagged?: flagged?,
        kind: kind,
        line: meta[:line],
        column: meta[:column]
      }
    end
  end

  defp cache_write(_node, _aliases), do: nil

  defp flagged?([:Cachex], fun), do: fun in @cachex_flagged
  defp flagged?([:Brando, :Cache], fun), do: fun in @brando_cache_flagged
  defp flagged?([:Brando, :Cache, _module], fun), do: fun in @brando_cache_module_flagged
  defp flagged?(_module, _fun), do: false

  defp kind([:Cachex], fun), do: kind(fun, @cachex_restores, @cachex_removals)
  defp kind([:Brando, :Cache], fun), do: kind(fun, @brando_cache_restores, @brando_cache_removals)
  defp kind([:Brando, :Cache, _module], fun), do: kind(fun, @brando_cache_module_restores, @brando_cache_module_removals)
  defp kind(_module, _fun), do: nil

  defp kind(fun, restores, removals) do
    cond do
      fun in restores -> :restore
      fun in removals -> :removal
      true -> nil
    end
  end

  defp issue_for(ctx, write) do
    format_issue(
      ctx,
      message:
        "Put back the cache `#{write.module}.#{write.fun}` changes: snapshot it in `setup` and write it back " <>
          "in `on_exit`, or call `preserve_cache/1`.",
      trigger: write.trigger,
      line_no: write.line,
      column: write.column
    )
  end

  defp removal_issue_for(ctx, {:on_exit, meta, _args}) do
    format_issue(
      ctx,
      message:
        "This `on_exit` removes cache entries and puts none back, which empties a key the test found filled: " <>
          "snapshot it in `setup` and write it back, or call `preserve_cache/1`.",
      trigger: "on_exit",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
