defmodule Brando.Credo.Check.TestCacheRestore do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["test/**/*_test.exs"]},
      restore_helpers: [:preserve_cache]
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
      `preserve_cache/1` from `Brando.Test.Support`:

          setup do
            preserve_cache([:identity, :seo])
          end

      This check sees direct writes in the test module: `Cachex.clear/1`,
      `Brando.Cache.put/update/reload_all`, and `set/update/put` on the
      `Brando.Cache.*` modules. Removing a single key (`del`, `evict`) is not
      flagged, since the cache refills it on the next read. A module passes once it has an `on_exit` that writes a cache
      (directly or through one of its own functions) or calls a restore
      helper. Writes made inside the code under test (a context function that
      refreshes the identity cache) are not visible to it; restore those too.
      """,
      params: [
        restore_helpers: "Function names that register a cache restore themselves."
      ]
    ]

  alias Credo.SourceFile

  @cachex_writes ~w(clear clear! put put! put_many put_many! del del! update update! reset reset! take take! incr incr! decr decr! expire expire! refresh refresh! touch touch!)a
  @cachex_flagged ~w(clear clear!)a
  # Writes that leave a value behind. Removing one key (`del`, `evict`) is
  # not flagged: the cache refills it on the next read. Both count as a
  # restore.
  @brando_cache_flagged ~w(put update reload_all)a
  @brando_cache_writes ~w(put update del reload_all)a
  @brando_cache_module_flagged ~w(set update put)a
  @brando_cache_module_writes ~w(set update put evict evict_schema evict_entry)a

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    ast = SourceFile.ast(source_file)
    aliases = collect_aliases(ast)
    helpers = Params.get(params, :restore_helpers, __MODULE__)

    if restores_cache?(ast, aliases, helpers) do
      []
    else
      ast
      |> flagged_writes(aliases)
      |> Enum.map(&issue_for(ctx, &1))
    end
  end

  # Writes outside `on_exit` bodies, in source order
  defp flagged_writes(ast, aliases) do
    {_ast, writes} =
      Macro.prewalk(ast, [], fn
        {:on_exit, _, _}, acc ->
          {nil, acc}

        node, acc ->
          case cache_write(node, aliases, :flag) do
            nil -> {node, acc}
            write -> {node, [write | acc]}
          end
      end)

    Enum.reverse(writes)
  end

  defp restores_cache?(ast, aliases, helpers) do
    exits = on_exit_bodies(ast)
    restoring_functions = restoring_functions(ast, aliases)

    calls_helper?(ast, helpers) or
      Enum.any?(exits, fn body ->
        writes_cache?(body, aliases) or Enum.any?(local_calls(body), &(&1 in restoring_functions))
      end)
  end

  defp on_exit_bodies(ast) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {:on_exit, _, args} = node, acc when is_list(args) -> {node, args ++ acc}
        node, acc -> {node, acc}
      end)

    bodies
  end

  defp calls_helper?(ast, helpers) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {name, _, args} = node, acc when is_atom(name) and is_list(args) -> {node, acc or name in helpers}
        node, acc -> {node, acc}
      end)

    found?
  end

  # Names of the module's own functions that write a cache
  defp restoring_functions(ast, aliases) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {kind, _, [head | body]} = node, acc when kind in [:def, :defp] ->
          if writes_cache?(body, aliases), do: {node, [function_name(head) | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp function_name({:when, _, [head | _]}), do: function_name(head)
  defp function_name({name, _, _}), do: name

  defp local_calls(ast) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {name, _, args} = node, acc when is_atom(name) and is_list(args) -> {node, [name | acc]}
        node, acc -> {node, acc}
      end)

    names
  end

  defp writes_cache?(ast, aliases) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, acc -> {node, acc or cache_write(node, aliases, :restore) != nil} end)

    found?
  end

  defp cache_write({{:., _, [{:__aliases__, meta, parts}, fun]}, _, args}, aliases, purpose) when is_list(args) do
    module = expand(parts, aliases)

    if write?(module, fun, purpose) do
      %{
        module: Enum.join(module, "."),
        trigger: Enum.join(parts, ".") <> ".#{fun}",
        fun: fun,
        line: meta[:line],
        column: meta[:column]
      }
    end
  end

  defp cache_write(_node, _aliases, _purpose), do: nil

  defp write?([:Cachex], fun, :flag), do: fun in @cachex_flagged
  defp write?([:Cachex], fun, :restore), do: fun in @cachex_writes
  defp write?([:Brando, :Cache], fun, :flag), do: fun in @brando_cache_flagged
  defp write?([:Brando, :Cache], fun, :restore), do: fun in @brando_cache_writes
  defp write?([:Brando, :Cache, _module], fun, :flag), do: fun in @brando_cache_module_flagged
  defp write?([:Brando, :Cache, _module], fun, :restore), do: fun in @brando_cache_module_writes
  defp write?(_module, _fun, _purpose), do: false

  defp expand([head | rest], aliases) do
    case Map.fetch(aliases, head) do
      {:ok, full} -> full ++ rest
      :error -> [head | rest]
    end
  end

  defp expand(parts, _aliases), do: parts

  defp collect_aliases(ast) do
    {_ast, aliases} = Macro.prewalk(ast, %{}, fn node, acc -> {node, add_alias(node, acc)} end)
    aliases
  end

  defp add_alias({:alias, _, [{:__aliases__, _, parts}]}, acc) when is_list(parts) do
    Map.put(acc, Enum.at(parts, -1), parts)
  end

  defp add_alias({:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [name]}]]}, acc) do
    Map.put(acc, name, parts)
  end

  defp add_alias({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]}, acc) do
    Enum.reduce(children, acc, fn
      {:__aliases__, _, parts}, acc -> Map.put(acc, Enum.at(parts, -1), base ++ parts)
      _child, acc -> acc
    end)
  end

  defp add_alias(_node, acc), do: acc

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
end
