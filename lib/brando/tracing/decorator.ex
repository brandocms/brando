defmodule Brando.Tracing.Decorator do
  @moduledoc """
  Wraps a function clause in a `Brando.Tracing.span/3`:

      use Brando.Tracing.Decorator

      @decorate span("brando.query.update", schema: :module, entry_id: :id)
      def update(context, module, name, id, params, opts) do

  Each attribute names an argument of the clause, or a path into one
  (`entry_id: [:entry, :id]`), or is a string or number to record as it is
  (`asset_type: "image"`), and is recorded as `brando.<key>`. A schema module
  is recorded by name. Values known only partway through the function go
  through `Brando.Tracing.set_attributes/1`.

  Only clauses with their own `@decorate` are traced.

  How: the function compiles exactly as written. At the end of the module it
  is made overridable, and each clause of its definition as it then stands
  gets an overriding clause with the same patterns and guards that calls
  `super` — inside the span for a decorated clause. So module attributes, `rescue` and everything else in the
  body keep their meaning. An argument read only by the attributes is unused
  in the function itself, so the compiler warns; record such a value with a
  literal or `Brando.Tracing.set_attributes/1`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Brando.Tracing.Decorator, only: [span: 1, span: 2]
      Module.register_attribute(__MODULE__, :decorate, accumulate: false)
      Module.register_attribute(__MODULE__, :brando_traced_clauses, accumulate: true)
      Module.register_attribute(__MODULE__, :brando_clause_counts, accumulate: false)
      @on_definition Brando.Tracing.Decorator
      @before_compile Brando.Tracing.Decorator
    end
  end

  @doc "Marks the next clause for tracing, as `@decorate span(name, attributes)`."
  defmacro span(name, attributes \\ []), do: Macro.escape({name, attributes})

  # A clause is known by its line and, for clauses of the function sharing a
  # line (one-liners, or clauses a macro defines at the caller's line), its
  # position among them.
  @doc false
  def __on_definition__(env, _kind, fun, args, _guards, body) do
    span = Module.get_attribute(env.module, :decorate)
    Module.delete_attribute(env.module, :decorate)

    if body != nil do
      key = {{fun, length(args)}, env.line}
      counts = Module.get_attribute(env.module, :brando_clause_counts) || %{}
      position = Map.get(counts, key, 0)
      Module.put_attribute(env.module, :brando_clause_counts, Map.put(counts, key, position + 1))

      if span do
        Module.put_attribute(env.module, :brando_traced_clauses, {{fun, length(args)}, {env.line, position}, span})
      end
    end
  end

  # The clauses come from the function's definition as it stands at the end
  # of the module: those a later `defoverridable` replaced are gone, and
  # module attributes in heads and guards hold the value they had where the
  # clause was written.
  @doc false
  defmacro __before_compile__(env) do
    traced = env.module |> Module.get_attribute(:brando_traced_clauses) |> Enum.group_by(&elem(&1, 0))

    for {{fun, arity} = function, decorations} <- traced,
        {:v1, kind, _meta, clauses} <- [Module.get_definition(env.module, function)],
        spans = Map.new(decorations, fn {_function, position, span} -> {position, span} end),
        positioned = positions(clauses),
        Enum.any?(positioned, fn {position, _clause} -> Map.has_key?(spans, position) end) do
      arguments = Macro.generate_arguments(arity, __MODULE__)

      overrides =
        for {position, {_meta, args, guards, _body}} <- positioned,
            do: override(kind, fun, args, guards, spans[position], arguments, env)

      quote do
        defoverridable [{unquote(fun), unquote(arity)}]
        unquote_splicing(overrides)
      end
    end
  end

  defp positions(clauses) do
    {positioned, _counts} =
      Enum.map_reduce(clauses, %{}, fn {meta, _, _, _} = clause, counts ->
        line = meta[:line]
        position = Map.get(counts, line, 0)
        {{{line, position}, clause}, Map.put(counts, line, position + 1)}
      end)

    positioned
  end

  # Matches what the original clause matches, binding each argument whole as
  # well, so `super` gets exactly what the caller passed.
  defp override(kind, fun, args, guards, span, arguments, env) do
    references = referenced(args, guards, span)

    heads =
      args
      |> Enum.map(&silence(&1, references))
      |> Enum.zip_with(arguments, fn pattern, argument -> quote(do: unquote(pattern) = unquote(argument)) end)

    head = guarded(quote(do: unquote(fun)(unquote_splicing(heads))), guards)
    call = quote(do: super(unquote_splicing(arguments)))
    body = traced(call, span, {env.module, fun, args})

    quote do: Kernel.unquote(kind)(unquote(head), do: unquote(body))
  end

  # `def f(x) when a when b` is either guard; it comes as [a, b].
  defp guarded(head, []), do: head

  defp guarded(head, guards) do
    [last | rest] = Enum.reverse(guards)
    quote do: unquote(head) when unquote(Enum.reduce(rest, last, &quote(do: unquote(&1) when unquote(&2))))
  end

  # Variables the override reads: those in guards, those named by the span's
  # attributes, those in a bitstring's size, and those repeated in the head
  # (matching one twice compares the values). The rest are matched but
  # unused, so each becomes a fresh variable no source name can clash with.
  defp referenced(patterns, guards, span) do
    {bound, in_types} = Enum.reduce(patterns, {[], []}, &pattern_variables/2)
    repeated = for {name, count} <- Enum.frequencies(bound), count > 1, do: name
    in_guards = for guard <- guards, {name, _meta, context} <- variables(guard), is_atom(context), do: name

    MapSet.new(in_guards ++ attribute_variables(span) ++ in_types ++ repeated)
  end

  defp attribute_variables(nil), do: []

  defp attribute_variables({_name, attributes}) do
    for {_key, spec} <- attributes, name = attribute_variable(spec), do: name
  end

  defp attribute_variable(name) when is_atom(name), do: name
  defp attribute_variable([name | _path]), do: name
  defp attribute_variable(_literal), do: nil

  defp variables(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {name, _meta, context} = variable, found when is_atom(name) and is_atom(context) -> {variable, [variable | found]}
        node, found -> {node, found}
      end)

    found
  end

  # Walks a head pattern the way the compiler reads it: the right of `::` is
  # a type, whose sizes read variables.
  defp pattern_variables({:"::", _meta, [value, type]}, {bound, in_types}) do
    pattern_variables(value, {bound, in_types ++ for({name, _, _} <- variables(type), do: name)})
  end

  defp pattern_variables({name, _meta, context}, {bound, in_types}) when is_atom(name) and is_atom(context),
    do: {[name | bound], in_types}

  defp pattern_variables({form, _meta, args}, acc) when is_list(args),
    do: Enum.reduce(args, pattern_variables(form, acc), &pattern_variables/2)

  defp pattern_variables({left, right}, acc), do: pattern_variables(right, pattern_variables(left, acc))
  defp pattern_variables(list, acc) when is_list(list), do: Enum.reduce(list, acc, &pattern_variables/2)
  defp pattern_variables(_literal, acc), do: acc

  defp silence({:"::", meta, [value, type]}, references), do: {:"::", meta, [silence(value, references), type]}

  defp silence({name, _meta, context} = variable, references) when is_atom(name) and is_atom(context) do
    if name in references or String.starts_with?(Atom.to_string(name), "_"),
      do: variable,
      else: Macro.unique_var(:"_#{name}", __MODULE__)
  end

  defp silence({form, meta, args}, references) when is_list(args),
    do: {silence(form, references), meta, Enum.map(args, &silence(&1, references))}

  defp silence({left, right}, references), do: {silence(left, references), silence(right, references)}
  defp silence(list, references) when is_list(list), do: Enum.map(list, &silence(&1, references))
  defp silence(literal, _references), do: literal

  defp traced(call, nil, _function), do: call

  defp traced(call, {name, attributes}, function) do
    attributes = for {key, spec} <- attributes, do: {:"brando.#{key}", value(spec, function)}

    quote do
      Brando.Tracing.span(unquote(name), %{unquote_splicing(attributes)}, fn -> unquote(call) end)
    end
  end

  defp value(literal, _function) when is_binary(literal) or is_number(literal), do: literal
  defp value(argument, function) when is_atom(argument), do: argument!(argument, function)

  defp value([argument | path], function) do
    quote do: Brando.Tracing.Decorator.dig(unquote(argument!(argument, function)), unquote(path))
  end

  @doc "Follows `path` through nested maps; `nil` when a step is missing. Used by the generated attributes."
  def dig(value, []), do: value
  def dig(%{} = map, [key | path]), do: dig(Map.get(map, key), path)
  def dig(_value, _path), do: nil

  # The variable as it appears in the clause's head, inside a pattern or a
  # default argument too.
  defp argument!(name, {module, fun, args}) do
    Enum.find_value(args, &find_variable(&1, name)) ||
      raise ArgumentError,
            "@decorate span: #{inspect(module)}.#{fun}/#{length(args)} has no argument named #{name}"
  end

  defp find_variable(ast, name) do
    {_ast, found} =
      Macro.prewalk(ast, nil, fn
        {^name, _meta, context} = variable, nil when is_atom(context) -> {variable, variable}
        node, found -> {node, found}
      end)

    found
  end
end
