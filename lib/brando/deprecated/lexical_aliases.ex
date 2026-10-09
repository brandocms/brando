defmodule Brando.Deprecated.LexicalAliases do
  @moduledoc false
  # Resolves module names in source code the way the compiler does, so the
  # 0.55 module renames (`mix brando.migrate55`, `mix brando.doctor`) can tell
  # which module a name refers to without compiling it.
  #
  # `annotate/1` puts two keys on every `{:__aliases__, meta, parts}` node:
  #
  #   * `:resolved_alias`: the module's segments (`[:Brando, :Upload]`), nil
  #     when they cannot be known (`unquote(m).X`), or `{:either, a, b}`
  #     when an alias declared inside an unknown macro's block may or may
  #     not reach it.
  #   * `:alias_binding`: the `{line, column}` of the declaration its first
  #     segment comes from: an `alias`, `require …, as:` or a nested
  #     `defmodule`. Nil for a name no alias reaches, `:module` for
  #     `__MODULE__`, `:brace` for a child of a multi-alias outside an
  #     `alias` (`require A.{B, C}`), and `:uncertain` for an `{:either, …}`.
  #
  # An alias applies from where it is declared to the end of its lexical
  # scope: a module body, a function, an `fn` or `->` clause, and the blocks
  # of `if`, `case`, `try`, `quote`, `test` and the other macros known to
  # scope them. An alias declared in the block of another macro may leak out
  # of it, so the names it could reach afterwards are `{:either, …}`. A
  # nested `defmodule Inner` aliases `Inner` inside and after it.
  #
  # The alias's own target, the base and children of a multi-alias, and a
  # nested module's name are annotated too; an `as:` option is not, being a
  # new name rather than a reference. Works on both `Code.string_to_quoted/2`
  # and Sourceror ASTs.

  @defs [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defn, :defnp, :defdelegate]
  @scoped @defs ++
            [:if, :unless, :case, :cond, :with, :for, :try, :receive, :quote, :test, :describe] ++
            [:setup, :setup_all, :scope]
  @module_like [:defimpl, :defprotocol]

  @doc "Annotates every module name in `ast`; see the module notes."
  def annotate(ast) do
    {ast, _env} = walk(ast, %{aliases: %{}, module: nil})
    ast
  end

  @doc "The module a name annotated by `annotate/1` resolves to, or nil."
  def module({:__aliases__, meta, _parts}), do: to_module(meta[:resolved_alias])
  def module(_node), do: nil

  @doc """
  Every module a name annotated by `annotate/1` may resolve to: one, both
  of an `{:either, …}`, or none.
  """
  def modules({:__aliases__, meta, _parts}) do
    case meta[:resolved_alias] do
      {:either, a, b} -> [a, b] |> Enum.map(&to_module/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      resolved -> List.wrap(to_module(resolved))
    end
  end

  def modules(_node), do: []

  @doc "The module for annotated segments, nil when not a plain list."
  def to_module([_ | _] = parts), do: Module.concat(parts)
  def to_module(_resolved), do: nil

  ## Walk

  # `{ast, env}`: env is what the code after `ast`, in the same scope, sees

  defp walk({:__aliases__, meta, parts}, env) do
    {resolved, binding} = resolve(parts, env)
    {{:__aliases__, annotate_meta(meta, resolved, binding), parts}, env}
  end

  defp walk({form, meta, [_ | _] = args} = node, env) when form in [:alias, :require] do
    case args do
      [{{:., _, [_base, :{}]}, _, children} = multi | rest] when is_list(children) ->
        {{_, _, children} = multi, _env} = walk(multi, env)
        env = if form == :alias, do: bind_children(env, children, node_position(node)), else: env
        {{form, meta, [multi | rest]}, env}

      [target | options] ->
        {target, _env} = walk(target, env)
        {{form, meta, [target | options]}, bind(env, form, target, options, node_position(node))}
    end
  end

  # `A.{B, C}`: the children are under the base
  defp walk({{:., dot_meta, [base, :{}]}, brace_meta, children} = node, env) when is_list(children) do
    {base, _env} = walk(base, env)
    {base_resolved, _binding} = resolved(base)
    children = Enum.map(children, &brace_child(&1, base_resolved, node_position(node)))
    {{{:., dot_meta, [base, :{}]}, brace_meta, children}, env}
  end

  defp walk({:defmodule, meta, [name, block]} = node, env) do
    {module, name, auto} = module_name(name, env, node_position(node))
    outer = if auto, do: put_alias(env, auto), else: env
    {block, _env} = walk(block, %{outer | module: module})
    {{:defmodule, meta, [name, block]}, outer}
  end

  defp walk({form, meta, args}, env) when form in @module_like and is_list(args) do
    {args, _env} = walk_list(args, %{env | module: :unknown})
    {{form, meta, args}, env}
  end

  defp walk({:fn, meta, clauses}, env) when is_list(clauses) do
    {clauses, _env} = walk_list(clauses, env)
    {{:fn, meta, clauses}, env}
  end

  defp walk({:->, meta, [left, right]}, env) do
    {left, inner} = walk(left, env)
    {right, _inner} = walk(right, inner)
    {{:->, meta, [left, right]}, env}
  end

  defp walk({:__block__, meta, statements}, env) when is_list(statements) do
    {statements, env} = walk_list(statements, env)
    {{:__block__, meta, statements}, env}
  end

  defp walk({call, meta, args}, env) when is_atom(call) and is_list(args) do
    cond do
      call in @scoped ->
        {args, _inner} = walk_list(args, env)
        {{call, meta, args}, env}

      do_block?(args) ->
        {args, inner} = walk_list(args, env)
        {{call, meta, args}, leak(env, inner)}

      true ->
        {args, env} = walk_list(args, env)
        {{call, meta, args}, env}
    end
  end

  defp walk({call, meta, args}, env) when is_list(args) do
    {call, env} = walk(call, env)
    {args, env} = walk_list(args, env)
    {{call, meta, args}, env}
  end

  defp walk({left, right}, env) do
    {left, env} = walk(left, env)
    {right, env} = walk(right, env)
    {{left, right}, env}
  end

  defp walk(list, env) when is_list(list), do: walk_list(list, env)
  defp walk(other, env), do: {other, env}

  defp walk_list(list, env), do: Enum.map_reduce(list, env, &walk/2)

  ## Declarations

  defp bind(env, form, target, options, position) do
    as = alias_as(options)

    cond do
      as == false -> env
      form == :alias and is_nil(as) -> put_target(env, target, nil, position)
      as -> put_target(env, target, as, position)
      true -> env
    end
  end

  defp put_target(env, {:__aliases__, meta, parts}, as, position) do
    resolved = meta[:resolved_alias]

    case {as || last_atom(parts) || last_atom(plain(resolved) || []), resolved} do
      {nil, _resolved} -> env
      {short, {:either, _, _}} -> put_alias(env, {short, nil, position})
      {short, resolved} -> put_alias(env, {short, resolved, position})
    end
  end

  # `alias :lists, as: L` and the like: a name the walk cannot follow
  defp put_target(env, _target, as, position) when is_atom(as) and not is_nil(as),
    do: put_alias(env, {as, nil, position})

  defp put_target(env, _target, _as, _position), do: env

  defp bind_children(env, children, position) do
    Enum.reduce(children, env, fn
      {:__aliases__, meta, parts}, env ->
        case last_atom(parts) do
          nil -> env
          short -> put_alias(env, {short, plain(meta[:resolved_alias]), position})
        end

      _child, env ->
        env
    end)
  end

  defp brace_child({:__aliases__, meta, parts}, base, position) do
    resolved = if is_list(base) and Enum.all?(parts, &is_atom/1), do: base ++ parts
    {:__aliases__, annotate_meta(meta, resolved, {:brace, position}), parts}
  end

  defp brace_child(child, _base, _position), do: child

  defp put_alias(env, {short, to, at}), do: %{env | aliases: Map.put(env.aliases, short, %{to: to, at: at})}

  # A nested `defmodule Inner` defines `Outer.Inner` and aliases `Inner`; at
  # the top level the name is expanded through the aliases in scope. The
  # module is nil at the top level and :unknown where it cannot be known.
  defp module_name({:__aliases__, meta, [first | rest] = parts}, %{module: outer}, position)
       when is_atom(first) and first != :"Elixir" and not is_nil(outer) do
    if is_list(outer) and Enum.all?(rest, &is_atom/1) do
      name = {:__aliases__, annotate_meta(meta, outer ++ parts, nil), parts}
      {outer ++ parts, name, {first, outer ++ [first], position}}
    else
      {:unknown, {:__aliases__, annotate_meta(meta, nil, nil), parts}, {first, nil, position}}
    end
  end

  defp module_name(name, env, _position) do
    {name, _env} = walk(name, env)
    {resolved, _binding} = resolved(name)
    {plain(resolved) || :unknown, name, nil}
  end

  # The names an unknown macro's block declared may or may not reach past it
  defp leak(env, inner) do
    Enum.reduce(inner.aliases, env, fn {short, entry}, env ->
      case env.aliases[short] do
        ^entry -> env
        outer -> %{env | aliases: Map.put(env.aliases, short, %{either: {entry, outer}})}
      end
    end)
  end

  ## Resolution

  defp resolve([{:__MODULE__, _, context} | rest], %{module: module}) when is_atom(context) do
    if is_list(module) and Enum.all?(rest, &is_atom/1), do: {module ++ rest, :module}, else: {nil, :module}
  end

  defp resolve([:"Elixir" | rest], _env) do
    if rest != [] and Enum.all?(rest, &is_atom/1), do: {rest, nil}, else: {nil, nil}
  end

  defp resolve([first | rest] = parts, env) when is_atom(first) do
    if Enum.all?(rest, &is_atom/1) do
      case env.aliases[first] do
        nil -> {parts, nil}
        %{to: to, at: at} -> {to && to ++ rest, at}
        %{either: {a, b}} -> {{:either, through(a, first, rest), through(b, first, rest)}, :uncertain}
      end
    else
      {nil, nil}
    end
  end

  defp resolve(_parts, _env), do: {nil, nil}

  defp through(nil, first, rest), do: [first | rest]
  defp through(%{to: to}, _first, rest), do: to && to ++ rest
  defp through(%{either: _}, _first, _rest), do: nil

  defp resolved({:__aliases__, meta, _}), do: {meta[:resolved_alias], meta[:alias_binding]}
  defp resolved(_node), do: {nil, nil}

  defp plain(resolved) when is_list(resolved), do: resolved
  defp plain(_resolved), do: nil

  defp annotate_meta(meta, resolved, binding), do: [{:resolved_alias, resolved}, {:alias_binding, binding} | meta]

  ## Helpers

  defp node_position({_, meta, _}), do: {meta[:line], meta[:column]}

  defp last_atom([_ | _] = parts) do
    case parts |> Enum.reverse() |> hd() do
      last when is_atom(last) -> last
      _ -> nil
    end
  end

  defp last_atom(_parts), do: nil

  defp alias_as([options | _]) do
    case literal(options) do
      options when is_list(options) -> Enum.find_value(options, &as_option/1)
      _ -> nil
    end
  end

  defp alias_as(_options), do: nil

  defp as_option({key, value}), do: if(literal(key) == :as, do: as_value(literal(value)))
  defp as_option(_option), do: nil

  defp as_value({:__aliases__, _, [as]}) when is_atom(as), do: as
  defp as_value(false), do: false
  defp as_value(_value), do: nil

  # The block is the last argument; a keyword list with `do` anywhere else
  # is not valid Elixir
  defp do_block?(args), do: Enum.any?(args, &(is_list(&1) and Enum.any?(&1, fn option -> do_key?(option) end)))

  defp do_key?({key, _value}), do: literal(key) == :do
  defp do_key?(_option), do: false

  defp literal({:__block__, _, [value]}), do: value
  defp literal(value), do: value
end
