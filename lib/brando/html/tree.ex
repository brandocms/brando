defmodule Brando.HTML.Tree do
  @moduledoc false
  # Brando's runtime HTML parsing: lexbor's HTML5 parser through `LazyHTML`,
  # as the `{tag, attrs, children}` trees `LazyHTML.Tree` describes. Text
  # nodes keep the whitespace between elements, so `<b>a</b> <i>b</i>`
  # keeps its space through a rewrite.

  @type t :: LazyHTML.Tree.t()
  @type html_node :: LazyHTML.Tree.html_node()

  @doc """
  The nodes of an HTML fragment.

  The fragment is parsed as a `<template>`'s content, which takes any
  element at its top level: table rows and cells without their table, as a
  row module renders them, stay rows and cells. A stray `</template>` ends
  that context, and what follows it is parsed as body content.
  """
  @spec parse_fragment(iodata()) :: t()
  def parse_fragment(html) do
    ["<template>", html]
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> case do
      [{"template", [], children} | rest] -> children ++ rest
      nodes -> nodes
    end
  end

  @doc "The nodes of a whole document, with the `html`, `head` and `body` a browser adds when missing."
  @spec parse_document(String.t()) :: t()
  def parse_document(html), do: html |> LazyHTML.from_document() |> LazyHTML.to_tree()

  @doc """
  HTML for `nodes`.

  The parser drops a line break that opens a `pre`, `textarea` or `listing`,
  as browsers do, so one that remains in the tree is written twice: the
  content reads the same when parsed again.
  """
  @spec to_html(t() | html_node()) :: String.t()
  def to_html(nodes) do
    nodes
    |> List.wrap()
    |> LazyHTML.Tree.postwalk(&keep_leading_newline/1)
    |> LazyHTML.Tree.to_html()
  end

  defp keep_leading_newline({tag, attrs, ["\n" <> _ = text | rest]}) when tag in ~w(pre textarea listing),
    do: {tag, attrs, ["\n" <> text | rest]}

  defp keep_leading_newline(node), do: node

  @doc """
  Updates every node, children before their parent. `fun` returns the node
  that takes its place, or a list of nodes (`[]` removes it).
  """
  @spec map(t(), (html_node() -> html_node() | t())) :: t()
  def map(nodes, fun), do: LazyHTML.Tree.postwalk(nodes, fun)

  @doc "The elements in `nodes` and their descendants that `fun` accepts, in document order."
  @spec find(t() | html_node(), (html_node() -> as_boolean(term()))) :: t()
  def find(nodes, fun), do: nodes |> List.wrap() |> find(fun, []) |> Enum.reverse()

  defp find([], _fun, acc), do: acc
  defp find([node | rest], fun, acc), do: find(rest, fun, find_node(node, fun, acc))

  defp find_node({tag, _attrs, children} = node, fun, acc) when is_binary(tag) do
    acc = if fun.(node), do: [node | acc], else: acc
    find(children, fun, acc)
  end

  defp find_node(_node, _fun, acc), do: acc

  @doc "The value of attribute `name`, or `nil`."
  @spec attr(html_node() | [{String.t(), String.t()}], String.t()) :: String.t() | nil
  def attr({_tag, attrs, _children}, name), do: attr(attrs, name)
  def attr(attrs, name) when is_list(attrs), do: Enum.find_value(attrs, fn {key, value} -> key == name && value end)
  def attr(_node, _name), do: nil

  @doc """
  The text in `nodes`, entities decoded. A `<br>` is a line break; comments
  and scripts give nothing.

  ## Options

    * `:sep` - put before each text node after the first. Defaults to `""`.
    * `:js` - include the text of `<script>` elements. Defaults to `false`.
    * `:style` - include the text of `<style>` elements. Defaults to `true`.
  """
  @spec text(t() | html_node(), keyword()) :: String.t()
  def text(nodes, opts \\ []) do
    opts = opts |> Keyword.validate!(sep: "", js: false, style: true) |> Map.new()
    nodes |> List.wrap() |> text([], opts) |> IO.iodata_to_binary()
  end

  defp text([], acc, _opts), do: acc
  defp text([node | rest], acc, opts), do: text(rest, text_node(node, acc, opts), opts)

  defp text_node(text, [], _opts) when is_binary(text), do: [text]
  defp text_node(text, acc, opts) when is_binary(text), do: [acc, opts.sep, text]
  defp text_node({"br", _, _}, acc, _opts), do: [acc, "\n"]
  defp text_node({"script", _, _}, acc, %{js: false}), do: acc
  defp text_node({"style", _, _}, acc, %{style: false}), do: acc
  defp text_node({tag, _, children}, acc, opts) when is_binary(tag), do: text(children, acc, opts)
  defp text_node(_comment, acc, _opts), do: acc
end
