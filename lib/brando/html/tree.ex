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

  The first element sets how the rest is read, as in a browser's
  `<template>`, so table parts mixed with other content lose some markup:
  after a `<col>` other elements are dropped (`<col><p>a</p>` gives the
  `col` alone), and after other content a row's `tr`, `td` and `th` tags are
  dropped and their text kept (`<p>x</p><tr><td>y</td></tr>` gives the `p`
  and `"y"`). Floki kept both.
  """
  @spec parse_fragment(iodata()) :: t()
  def parse_fragment(html) do
    {html, noscripts} = html |> IO.iodata_to_binary() |> mask_noscripts()

    ("<template>" <> html)
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> case do
      [{"template", [], children} | rest] -> children ++ rest
      nodes -> nodes
    end
    |> restore_noscripts(noscripts)
  end

  @doc "The nodes of a whole document, with the `html`, `head` and `body` a browser adds when missing."
  @spec parse_document(String.t()) :: t()
  def parse_document(html) do
    {html, noscripts} = mask_noscripts(html)
    html |> LazyHTML.from_document() |> LazyHTML.to_tree() |> restore_noscripts(noscripts)
  end

  # lexbor parses with scripting off, where a `<noscript>`'s content is
  # markup: an element left open inside it takes in the rest of the input,
  # and in `<head>` an `<img>` inside it ends the head. Browsers, with
  # scripting on, read the content as text up to the first `</noscript>`.
  # So each noscript is parsed as an empty `<template>`, marked with an
  # attribute, and turned back into the noscript with its content parsed on
  # its own. A template, as an empty noscript does not, stays where it is
  # in a head, body or table: lexbor puts a `<link>` after an empty
  # `<noscript></noscript>` in head inside it. Comments and the other
  # elements whose content is text are matched too, so a `<noscript>` in
  # their text stays text.
  @noscript_attr "data-brando-noscript"
  @raw_text ~r/<!--.*?-->|<(script|style|textarea|title|xmp|iframe|noembed|noframes|noscript)(?=[\s\/>])(?:"[^"]*"|'[^']*'|[^'">])*>.*?<\/\1\s*>/is
  @noscript ~r/\A<noscript((?:"[^"]*"|'[^']*'|[^'">])*)>(.*)<\/noscript\s*>\z/is

  defp mask_noscripts(html) do
    if html =~ ~r/<noscript/i do
      @raw_text
      |> Regex.split(html, include_captures: true)
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, &mask_noscript/2)
      |> then(fn {parts, noscripts} -> {IO.iodata_to_binary(parts), noscripts} end)
    else
      {html, %{}}
    end
  end

  # Odd parts are the raw text elements and comments the split matched.
  defp mask_noscript({raw_text, index}, noscripts) when rem(index, 2) == 1 do
    case Regex.run(@noscript, raw_text) do
      [_, attrs, content] ->
        id = Integer.to_string(map_size(noscripts))
        {~s(<template #{@noscript_attr}="#{id}"#{attrs}></template>), Map.put(noscripts, id, content)}

      nil ->
        {raw_text, noscripts}
    end
  end

  defp mask_noscript({markup, _index}, noscripts), do: {markup, noscripts}

  defp restore_noscripts(nodes, noscripts) when noscripts == %{}, do: nodes

  defp restore_noscripts(nodes, noscripts) do
    map(nodes, fn
      {"template", attrs, _children} = node ->
        with {{_, id}, attrs} <- List.keytake(attrs, @noscript_attr, 0),
             {:ok, content} <- Map.fetch(noscripts, id) do
          {"noscript", attrs, parse_fragment(content)}
        else
          _ -> node
        end

      node ->
        node
    end)
  end

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
