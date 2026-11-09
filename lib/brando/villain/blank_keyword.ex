defmodule Brando.Villain.BlankKeyword do
  @moduledoc """
  Gives Liquid's `blank` keyword the meaning templates expect.

  Liquex resolves `blank` with plain-Ruby semantics, where nothing is blank,
  so `{% if x != blank %}` is always true. Brando templates use the keyword
  to hide empty vars: here `blank` matches `nil`, `false`, `""`, `[]` and
  `%{}`. A string of only whitespace is not blank, and `empty` keeps
  Liquid's meaning.

  `parse/2` parses with Liquex, then `rewrite/1` changes the document:

    * each `x == blank` and `x != blank` in an `{% if %}`, `{% elsif %}`
      or `{% unless %}` becomes a blank test that `eval/2` evaluates, and
      those tags render through `IfTag` and `UnlessTag` here, which
      evaluate every other condition with Liquex;
    * `{% when blank %}` becomes one `when` value per blank value.

  The test cannot be written as Liquex comparisons: comparing a Decimal
  with `nil` or `false` raises in Liquex, and Liquex conditions have no
  negation for `x == blank`.
  """

  alias __MODULE__.IfTag
  alias __MODULE__.UnlessTag

  @blank %Liquex.Special{type: :blank}
  @blank_values [nil, false, "", [], %{}]
  @tags %{Liquex.Tag.IfTag => IfTag, Liquex.Tag.UnlessTag => UnlessTag}

  @doc """
  Parses a template with `Liquex.parse/2` and rewrites its `blank`
  comparisons. Only a template that spells `blank` is walked.
  """
  @spec parse(String.t(), module()) :: {:ok, Liquex.document_t()} | {:error, String.t(), pos_integer()}
  def parse(template, parser) do
    case Liquex.parse(template, parser) do
      {:ok, document} -> {:ok, if(String.contains?(template, "blank"), do: rewrite(document), else: document)}
      error -> error
    end
  end

  @doc """
  Rewrites the `blank` comparisons in a parsed Liquex document.
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

  # Only an `if`'s or `unless`'s conditions get blank tests: another tag
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

  defp condition(left: left, op: op, right: [literal: @blank]) when op in [:==, :!=], do: {__MODULE__, op, left}
  defp condition(left: [literal: @blank], op: op, right: right) when op in [:==, :!=], do: {__MODULE__, op, right}
  defp condition(chain) when is_list(chain), do: Enum.map(chain, &condition/1)
  defp condition(term), do: term

  defp when_values({:literal, @blank}), do: Enum.map(@blank_values, &{:literal, &1})
  defp when_values(expression), do: [rewrite(expression)]

  @doc """
  Evaluates an `if` or `unless` condition as Liquex does, with the blank
  tests `rewrite/1` leaves in it.
  """
  @spec eval(term(), Liquex.Context.t()) :: {boolean(), Liquex.Context.t()}
  def eval({__MODULE__, op, operand}, context) do
    {value, context} = Liquex.Argument.eval(operand, context)
    {blank?(value) == (op == :==), context}
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
  True for the values `blank` matches.
  """
  @spec blank?(term()) :: boolean()
  def blank?(value) when value in [nil, false, "", []], do: true
  def blank?(map) when is_map(map) and not is_struct(map), do: map_size(map) == 0
  def blank?(_), do: false

  defmodule IfTag do
    @moduledoc false
    # `Liquex.Tag.IfTag.render/2`, with conditions evaluated by
    # `Brando.Villain.BlankKeyword.eval/2`.

    alias Brando.Villain.BlankKeyword

    def render([{:expression, expression}, {:contents, contents} | tail], context),
      do: branch(expression, contents, tail, context)

    def render([{:elsif, [expression: expression, contents: contents]} | tail], context),
      do: branch(expression, contents, tail, context)

    def render([else: [contents: contents]], context), do: Liquex.Render.render!(contents, context)
    def render([], context), do: {[], context}

    defp branch(expression, contents, tail, context) do
      {truthy?, context} = BlankKeyword.eval(expression, context)
      if truthy?, do: Liquex.Render.render!(contents, context), else: render(tail, context)
    end
  end

  defmodule UnlessTag do
    @moduledoc false
    # `Liquex.Tag.UnlessTag.render/2`, whose `elsif` and `else` render as
    # an `if`'s do.

    alias Brando.Villain.BlankKeyword

    def render([{:expression, expression}, {:contents, contents} | tail], context) do
      {truthy?, context} = BlankKeyword.eval(expression, context)
      if truthy?, do: IfTag.render(tail, context), else: Liquex.Render.render!(contents, context)
    end
  end
end
