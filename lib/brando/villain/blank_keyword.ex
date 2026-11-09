defmodule Brando.Villain.BlankKeyword do
  @moduledoc """
  Gives Liquid's `blank` keyword the meaning templates expect.

  Liquex resolves `blank` with plain-Ruby semantics, where nothing is blank,
  so `{% if x != blank %}` is always true. Brando templates use the keyword
  to hide empty vars: `blank` matches `nil`, `""`, `false`, `[]` and `%{}`
  here. A string of only whitespace is not blank.

  `rewrite/1` turns each comparison with `blank` in a parsed document into
  comparisons Liquex evaluates:

    * `x == blank` becomes `(x == nil or x == empty or x == false)`
    * `x != blank` becomes `(x != nil and x != empty and x != false)`
    * `{% when blank %}` matches each blank value

  The expansion is a nested expression list, which Liquex evaluates as a
  group, so it keeps its place in an `and`/`or` chain.
  """

  @blank %Liquex.Special{type: :blank}
  @blank_values [nil, "", false, [], %{}]

  @doc """
  Parses a template with `Liquex.parse/2`, then rewrites its `blank`
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
  def rewrite(left: left, op: op, right: [literal: @blank]) when op in [:==, :!=], do: expand(rewrite(left), op)
  def rewrite(left: [literal: @blank], op: op, right: right) when op in [:==, :!=], do: expand(rewrite(right), op)

  def rewrite({:when, [expression: expressions, contents: contents]}) do
    expressions = Enum.flat_map(expressions, &when_values/1)
    {:when, [expression: expressions, contents: rewrite(contents)]}
  end

  def rewrite([head | tail]), do: [rewrite(head) | rewrite(tail)]
  def rewrite(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> rewrite() |> List.to_tuple()
  def rewrite(term), do: term

  defp expand(operand, :==), do: compare_each(operand, :==, :or)
  defp expand(operand, :!=), do: compare_each(operand, :!=, :and)

  defp compare_each(operand, op, joiner) do
    [nil, Liquex.Special.empty(), false]
    |> Enum.map(&[left: operand, op: op, right: [literal: &1]])
    |> Enum.intersperse(joiner)
  end

  defp when_values({:literal, @blank}), do: Enum.map(@blank_values, &{:literal, &1})
  defp when_values(expression), do: [rewrite(expression)]
end
