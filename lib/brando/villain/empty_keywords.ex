defmodule Brando.Villain.EmptyKeywords do
  @moduledoc """
  Gives Liquid's `empty` and `blank` keywords the meaning templates expect.

  Liquex resolves both with plain-Ruby semantics: nothing is `blank`, so
  `{% if x != blank %}` is always true, and `nil` is not `empty`. Brando
  templates use the keywords to hide markup around a var with no value:

    * `empty` matches `nil`, `""`, `[]` and `%{}`;
    * `blank` matches those and `false`.

  A string of only whitespace matches neither.

  `parse/2` parses with Liquex, then `rewrite/1` changes the document:

    * each `==` or `!=` comparison with `empty` or `blank` in an
      `{% if %}`, `{% elsif %}` or `{% unless %}` becomes a test that
      `eval/2` evaluates, and those tags render through `IfTag` and
      `UnlessTag` here, which evaluate every other condition with Liquex;
    * `{% when empty %}` and `{% when blank %}` become one `when` value per
      value the keyword matches.

  The tests cannot be written as Liquex comparisons: comparing a Decimal
  with `nil` or `false` raises in Liquex, and Liquex conditions have no
  negation for `x == blank`.
  """

  alias __MODULE__.IfTag
  alias __MODULE__.UnlessTag

  @keywords %{
    %Liquex.Special{type: :empty} => :empty,
    %Liquex.Special{type: :blank} => :blank
  }
  @values %{empty: [nil, "", [], %{}], blank: [nil, false, "", [], %{}]}
  @tags %{Liquex.Tag.IfTag => IfTag, Liquex.Tag.UnlessTag => UnlessTag}

  @doc """
  Parses a template with `Liquex.parse/2` and rewrites its `empty` and
  `blank` comparisons. Only a template that spells one of them is walked.
  """
  @spec parse(String.t(), module()) :: {:ok, Liquex.document_t()} | {:error, String.t(), pos_integer()}
  def parse(template, parser) do
    case Liquex.parse(template, parser) do
      {:ok, document} ->
        {:ok, if(String.contains?(template, ["empty", "blank"]), do: rewrite(document), else: document)}

      error ->
        error
    end
  end

  @doc """
  Rewrites the `empty` and `blank` comparisons in a parsed Liquex document.
  """
  @spec rewrite(term()) :: term()
  def rewrite({{:tag, tag}, arguments}) when is_map_key(@tags, tag),
    do: {{:tag, Map.fetch!(@tags, tag)}, if_arguments(arguments)}

  # Brando's parser wraps each tag in `Brando.Villain.Tags.Output`.
  def rewrite({{:tag, Brando.Villain.Tags.Output} = output, [tag: tag, contents: arguments] ++ rest})
      when is_map_key(@tags, tag),
      do: {output, [tag: Map.fetch!(@tags, tag), contents: if_arguments(arguments)] ++ rewrite(rest)}

  def rewrite({:when, [expression: expressions, contents: contents]}) do
    expressions = Enum.flat_map(expressions, &when_values/1)
    {:when, [expression: expressions, contents: rewrite(contents)]}
  end

  def rewrite([head | tail]), do: [rewrite(head) | rewrite(tail)]
  def rewrite(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> rewrite() |> List.to_tuple()
  def rewrite(term), do: term

  # Only an `if`'s or `unless`'s conditions get keyword tests: another tag
  # that evaluates a condition does so with Liquex, which has no clause for
  # them.
  defp if_arguments(arguments) do
    Enum.map(arguments, fn
      {:expression, expression} ->
        {:expression, condition(expression)}

      {:elsif, [expression: expression, contents: contents]} ->
        {:elsif, [expression: condition(expression), contents: rewrite(contents)]}

      {key, value} ->
        {key, rewrite(value)}
    end)
  end

  defp condition(left: left, op: op, right: [literal: special]) when op in [:==, :!=] and is_map_key(@keywords, special),
    do: {__MODULE__, Map.fetch!(@keywords, special), op, left}

  defp condition(left: [literal: special], op: op, right: right) when op in [:==, :!=] and is_map_key(@keywords, special),
    do: {__MODULE__, Map.fetch!(@keywords, special), op, right}

  defp condition(chain) when is_list(chain), do: Enum.map(chain, &condition/1)
  defp condition(term), do: term

  defp when_values({:literal, special}) when is_map_key(@keywords, special),
    do: Enum.map(Map.fetch!(@values, Map.fetch!(@keywords, special)), &{:literal, &1})

  defp when_values(expression), do: [rewrite(expression)]

  @doc """
  Evaluates an `if` or `unless` condition as Liquex does, with the keyword
  tests `rewrite/1` leaves in it.
  """
  @spec eval(term(), Liquex.Context.t()) :: {boolean(), Liquex.Context.t()}
  def eval({__MODULE__, keyword, op, operand}, context) do
    {value, context} = Liquex.Argument.eval(operand, context)
    matches? = if keyword == :empty, do: empty?(value), else: blank?(value)
    {matches? == (op == :==), context}
  end

  def eval([left: _, op: _, right: _] = comparison, context), do: Liquex.Expression.eval(comparison, context)

  # An `and`/`or` chain, as Liquex evaluates it: right to left, every term
  # evaluated, so `a or b and c` is `a or (b and c)`.
  def eval([_ | _] = chain, context) do
    [[last] | rest] = chain |> Enum.chunk_every(2) |> Enum.reverse()
    {acc, context} = eval(last, context)

    Enum.reduce(rest, {acc, context}, fn [expression, joiner], {acc, context} ->
      {value, context} = eval(expression, context)
      {if(joiner == :and, do: value and acc, else: value or acc), context}
    end)
  end

  def eval(expression, context), do: Liquex.Expression.eval(expression, context)

  @doc """
  True for the values `empty` matches.
  """
  @spec empty?(term()) :: boolean()
  def empty?(value) when value in [nil, "", []], do: true
  def empty?(map) when is_map(map) and not is_struct(map), do: map_size(map) == 0
  def empty?(_), do: false

  @doc """
  True for the values `blank` matches.
  """
  @spec blank?(term()) :: boolean()
  def blank?(false), do: true
  def blank?(value), do: empty?(value)

  defmodule IfTag do
    @moduledoc false
    # `Liquex.Tag.IfTag.render/2`, with conditions evaluated by
    # `Brando.Villain.EmptyKeywords.eval/2`.

    alias Brando.Villain.EmptyKeywords

    def render([{:expression, expression}, {:contents, contents} | tail], context),
      do: branch(expression, contents, tail, context)

    def render([{:elsif, [expression: expression, contents: contents]} | tail], context),
      do: branch(expression, contents, tail, context)

    def render([else: [contents: contents]], context), do: Liquex.Render.render!(contents, context)
    def render([], context), do: {[], context}

    defp branch(expression, contents, tail, context) do
      {truthy?, context} = EmptyKeywords.eval(expression, context)
      if truthy?, do: Liquex.Render.render!(contents, context), else: render(tail, context)
    end
  end

  defmodule UnlessTag do
    @moduledoc false
    # `Liquex.Tag.UnlessTag.render/2`, whose `elsif` and `else` render as
    # an `if`'s do.

    alias Brando.Villain.EmptyKeywords

    def render([{:expression, expression}, {:contents, contents} | tail], context) do
      {truthy?, context} = EmptyKeywords.eval(expression, context)
      if truthy?, do: IfTag.render(tail, context), else: Liquex.Render.render!(contents, context)
    end
  end
end
