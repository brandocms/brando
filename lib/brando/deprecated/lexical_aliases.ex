defmodule Brando.Deprecated.LexicalAliases do
  @moduledoc false
  # Resolves module names in source code the way the compiler does, so the
  # 0.55 module renames (`mix brando.migrate55`, `mix brando.doctor`) can tell
  # which module a name refers to without compiling it.
  #
  # `annotate/1` puts two keys on every `{:__aliases__, meta, parts}` node:
  #
  #   * `:resolved_alias`: the module's segments (`[:Brando, :Upload]`), nil
  #     when they cannot be known (`unquote(m).X`), or `{:either, [a, b]}`
  #     when an alias declared inside an unknown macro's block may or may
  #     not reach it.
  #   * `:alias_binding`: the `{line, column}` of the declaration its first
  #     segment comes from: an `alias`, `require …, as:` or a nested
  #     `defmodule`. Nil for a name no alias reaches, `:module` for
  #     `__MODULE__`, `:brace` for a child of a multi-alias outside an
  #     `alias` (`require A.{B, C}`), and `:uncertain` for an `{:either, …}`.
  #
  # An alias applies from where it is declared to the end of its lexical
  # scope: a module body, a function, an `fn` or `->` clause, and each block
  # (`do`, `else`, `rescue`, `after`, …) of `if`, `try`, `def`, `with`,
  # `quote`, `test` and the other macros known to scope them, local or
  # through `Kernel.`. An alias declared in the block of another macro,
  # local or remote, may leak out of it, so the names it could reach
  # afterwards are `{:either, …}`. A nested `defmodule Inner` aliases
  # `Inner` inside and after it.
  #
  # Imports are scoped the same way: a local call after one carries
  # `imports: [%{module, only, except}]`. Template sigils (`~H`, …) and
  # `embed_templates` calls carry `:lexical_env`, the aliases where they
  # are written, for `template_names/1` and `names_in_text/3`.
  #
  # The alias's own target, the base and children of a multi-alias, and a
  # nested module's name are annotated too; an `as:` option is not, being a
  # new name rather than a reference. Works on both `Code.string_to_quoted/2`
  # and Sourceror ASTs.

  alias Brando.Deprecated.TemplateCode

  @defs [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defn, :defnp, :defdelegate]
  @scoped @defs ++
            [:if, :unless, :case, :cond, :with, :for, :try, :receive, :quote, :test, :describe] ++
            [:setup, :setup_all, :scope]
  @module_like [:defimpl, :defprotocol]
  @template_calls [:sigil_H, :sigil_F, :sigil_L, :sigil_E, :embed_templates]
  @heredocs [~s("""), ~s(''')]

  @doc """
  Annotates every module name in `ast`; see the module notes. Starts from
  `lexical_env`, a template's `:lexical_env`, when given.
  """
  def annotate(ast, lexical_env \\ %{}) do
    {ast, _env} = walk(ast, Map.merge(%{aliases: %{}, module: nil, imports: []}, lexical_env))
    ast
  end

  @doc """
  The module a name annotated by `annotate/1` resolves to, or nil. A module
  spelled as an atom (`:"Elixir.EEx"`) is that module.
  """
  def module({:__aliases__, meta, _parts}), do: to_module(meta[:resolved_alias])
  def module({:__block__, _, [atom]}) when is_atom(atom), do: module(atom)

  def module(atom) when is_atom(atom) do
    if atom |> Atom.to_string() |> String.starts_with?("Elixir."), do: atom
  end

  def module(_node), do: nil

  @doc """
  Every module a name annotated by `annotate/1` may resolve to: one, each
  of an `{:either, …}`, or none.
  """
  def modules({:__aliases__, meta, _parts}) do
    case meta[:resolved_alias] do
      {:either, candidates} -> candidates |> Enum.map(&to_module/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      resolved -> List.wrap(to_module(resolved))
    end
  end

  def modules(_node), do: []

  @doc "The module for annotated segments, nil when not a plain list."
  def to_module([_ | _] = parts), do: Module.concat(parts)
  def to_module(_resolved), do: nil

  @doc """
  The module names written in a template sigil (`~H`, `~F`, `~L`, `~E`)
  annotated by `annotate/1`: `[%{name, resolved, line}]`, resolved through
  the aliases where the sigil is written. Text that looks like a module
  name counts, so prose such as `Store` in a heading is read as one too.
  """
  def template_names({sigil, meta, [{:<<>>, _, parts} | _]}) do
    text = parts |> Enum.filter(&is_binary/1) |> Enum.join()
    first_line = meta[:line] + if(meta[:delimiter] in @heredocs, do: 1, else: 0)
    names_in_text(text, meta[:lexical_env], first_line, sigil_mode(sigil))
  end

  def template_names(_node), do: []

  defp sigil_mode(:sigil_H), do: :heex
  defp sigil_mode(:sigil_F), do: :surface
  defp sigil_mode(_sigil), do: :eex

  @doc """
  The module names written in `text` (a template file compiled into a
  module by the `embed_templates` call whose metadata holds `lexical_env`),
  with its first line numbered `first_line`; see `template_names/1`. Only
  code counts (`Brando.Deprecated.TemplateCode`): `mode` is `:heex`, where
  `{…}` interpolates, or `:eex`.
  """
  def names_in_text(text, lexical_env, first_line, mode \\ :heex)
  def names_in_text(_text, nil, _first_line, _mode), do: []

  def names_in_text(text, lexical_env, first_line, mode) do
    text
    |> TemplateCode.segments(mode)
    |> Enum.flat_map(fn
      {:tag, name, line} -> [name_entry(name, lexical_env, first_line + line)]
      {:code, code, line} -> names_in_code(code, lexical_env, first_line + line)
    end)
  end

  # The module names in a template's Elixir; string literals and comments
  # are not code. A fragment that does not parse alone (`<%= if x do %>`)
  # is read with its strings, but for their interpolations, and comments
  # blanked out.
  defp names_in_code(code, lexical_env, line) do
    case Code.string_to_quoted(code, line: line, columns: false, emit_warnings: false) do
      {:ok, ast} ->
        {_ast, names} =
          ast
          |> annotate(lexical_env)
          |> Macro.prewalk([], fn
            {:__aliases__, meta, parts} = node, names ->
              {node,
               [
                 %{name: Enum.map_join(parts, ".", &segment/1), resolved: meta[:resolved_alias], line: meta[:line]}
                 | names
               ]}

            node, names ->
              {node, names}
          end)

        Enum.reverse(names)

      {:error, _} ->
        code
        |> String.replace(~r/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|#[^\n]*/, &blank/1)
        |> names_in_words(lexical_env, line)
    end
  end

  defp names_in_words(text, lexical_env, first_line) do
    ~r/(?<![\w.@:\-])[A-Z]\w*(?:\.[A-Z]\w*)*/u
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{at, length}] ->
      name_entry(binary_part(text, at, length), lexical_env, first_line + newline_count(binary_part(text, 0, at)))
    end)
  end

  defp name_entry(name, lexical_env, line) do
    {resolved, _binding} = name |> String.split(".") |> Enum.map(&String.to_atom/1) |> resolve(lexical_env)
    %{name: name, resolved: resolved, line: line}
  end

  defp newline_count(text), do: text |> :binary.matches("\n") |> length()

  # A string literal's interpolations, a comment's nothing, on as many lines
  defp blank(literal) do
    interpolations = ~r/#\{([^}]*)\}/ |> Regex.scan(literal, capture: :all_but_first) |> Enum.map_join(" ", &hd/1)
    String.replace(interpolations, "\n", " ") <> String.duplicate("\n", newline_count(literal))
  end

  defp segment({name, _, _}), do: name
  defp segment(name), do: name

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

  defp walk({:import, meta, [target | options]}, env) do
    {target, _env} = walk(target, env)
    {{:import, meta, [target | options]}, put_import(env, target, options)}
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
    meta = annotate_imports(meta, env)
    meta = if call in @template_calls, do: [{:lexical_env, Map.take(env, [:aliases, :module])} | meta], else: meta
    {args, env} = walk_call({call in @scoped, call}, args, env)
    {{call, meta, args}, env}
  end

  # `Kernel.if x do … end` scopes its blocks as `if` does; another remote
  # macro's do block may leak what it declares
  defp walk({{:., dot_meta, [remote, name]}, meta, args}, env) when is_atom(name) and is_list(args) do
    {remote, _env} = walk(remote, env)
    {args, env} = walk_call({module(remote) == Kernel and name in @scoped, name}, args, env)
    {{{:., dot_meta, [remote, name]}, meta, args}, env}
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

  # A call's arguments, then each of its `do`/`else`/`rescue`/… blocks
  # from where they start, after the arguments (a `with`'s `else` before
  # its clauses): a scoping macro keeps what they declare, another macro
  # may leak it
  defp walk_call({scoped?, call}, args, env) do
    case split_blocks(args) do
      {args, nil} ->
        walk_list(args, env)

      {head, blocks} ->
        {head, head_env} = walk_list(head, env)
        {blocks, inners} = blocks |> Enum.map(&walk_block(&1, {call, env, head_env})) |> Enum.unzip()
        {head ++ [blocks], if(scoped?, do: head_env, else: leak(head_env, inners))}
    end
  end

  defp walk_block({key, value}, envs) do
    {value, inner} = walk(value, block_env(literal(key), envs))
    {{key, value}, inner}
  end

  defp walk_block(other, {_call, _env, head_env}), do: {other, head_env}

  defp block_env(:else, {:with, env, _head_env}), do: env
  defp block_env(_key, {_call, _env, head_env}), do: head_env

  defp split_blocks([_ | _] = args) do
    {head, [last]} = Enum.split(args, -1)
    if is_list(last) and Enum.any?(last, &do_key?/1), do: {head, last}, else: {args, nil}
  end

  defp split_blocks(args), do: {args, nil}

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

    case as || last_atom(parts) || last_atom(plain(resolved) || []) do
      nil -> env
      short -> put_alias(env, {short, resolved, position})
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
          short -> put_alias(env, {short, meta[:resolved_alias], position})
        end

      _child, env ->
        env
    end)
  end

  defp brace_child({:__aliases__, meta, parts}, base, position) do
    resolved =
      cond do
        not Enum.all?(parts, &is_atom/1) -> nil
        is_list(base) -> base ++ parts
        match?({:either, _}, base) -> {:either, Enum.map(elem(base, 1), &(&1 && &1 ++ parts))}
        true -> nil
      end

    {:__aliases__, annotate_meta(meta, resolved, {:brace, position}), parts}
  end

  defp brace_child(child, _base, _position), do: child

  # `import Brando.HTML, only: […]`: `%{module, only, except}` per module it
  # may name, for the local calls after it. A module imported again is
  # imported as the last import says.
  defp put_import(env, target, options) do
    options = plain_term(List.first(options) || [])
    keyword = if Keyword.keyword?(options), do: options, else: []
    modules = modules(target)
    specs = for module <- modules, do: %{module: module, only: keyword[:only], except: keyword[:except]}
    %{env | imports: Enum.reject(env.imports, &(&1.module in modules)) ++ specs}
  end

  defp annotate_imports(meta, %{imports: []}), do: meta
  defp annotate_imports(meta, %{imports: imports}), do: [{:imports, imports} | meta]

  # A name that may be either module is aliased as either
  defp put_alias(env, {short, {:either, candidates}, at}),
    do: %{env | aliases: Map.put(env.aliases, short, %{either: Enum.map(candidates, &%{to: &1, at: at})})}

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

  # What an unknown macro's blocks declared may or may not reach past it:
  # a name each block left differently is any of them, or the one before
  defp leak(env, inners) do
    shorts = inners |> Enum.flat_map(&Map.keys(&1.aliases)) |> Enum.uniq()

    aliases =
      Enum.reduce(shorts, env.aliases, fn short, aliases ->
        candidates = (inners ++ [env]) |> Enum.flat_map(&candidates(&1.aliases[short])) |> Enum.uniq()

        case candidates do
          [nil] -> aliases
          [only] -> Map.put(aliases, short, only)
          _ -> Map.put(aliases, short, %{either: candidates})
        end
      end)

    %{env | aliases: aliases, imports: Enum.uniq(env.imports ++ Enum.flat_map(inners, & &1.imports))}
  end

  defp candidates(%{either: candidates}), do: candidates
  defp candidates(entry), do: [entry]

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
        %{either: candidates} -> {{:either, Enum.map(candidates, &through(&1, first, rest))}, :uncertain}
      end
    else
      {nil, nil}
    end
  end

  defp resolve(_parts, _env), do: {nil, nil}

  defp through(nil, first, rest), do: [first | rest]
  defp through(%{to: to}, _first, rest), do: to && to ++ rest

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

  defp do_key?({key, _value}), do: literal(key) == :do
  defp do_key?(_option), do: false

  defp literal({:__block__, _, [value]}), do: value
  defp literal(value), do: value

  # A literal without Sourceror's :__block__ wrappers
  defp plain_term({:__block__, _, [value]}), do: plain_term(value)
  defp plain_term({left, right}), do: {plain_term(left), plain_term(right)}
  defp plain_term(list) when is_list(list), do: Enum.map(list, &plain_term/1)
  defp plain_term(value), do: value
end
