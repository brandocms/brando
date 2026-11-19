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
  # `<noscript></noscript>` in head inside it.
  #
  # The noscripts are found by a scan that follows the tokenizer far enough
  # to see a `<noscript>` only where it is a tag: not in an attribute value,
  # a comment, or the text of a script, style, textarea, title and the other
  # elements whose content is text, each of which runs to the end of the
  # input when left open. Inside `<svg>` and `<math>`, where a noscript is
  # an element like any other, nothing is masked. Each step moves forward,
  # so the scan is linear. The marker carries a random value made for the
  # call, so a template already in the input is never taken for one.
  @noscript_attr "data-brando-noscript"
  @space [?\t, ?\n, ?\f, ?\r, ?\s]
  @text_elements ~w(style textarea title xmp iframe noembed noframes)

  defp mask_noscripts(html) do
    if html =~ ~r/<noscript/i do
      nonce = 10 |> :crypto.strong_rand_bytes() |> Base.encode32(case: :lower, padding: false)

      html
      |> ascii_downcase()
      |> data(0, [])
      |> Enum.reverse()
      |> Enum.reduce({[], %{}, 0}, fn {from, to, attrs, content}, {parts, noscripts, at} ->
        id = "#{nonce}-#{map_size(noscripts)}"
        marker = [~s(<template #{@noscript_attr}="), id, ?", :binary.part(html, attrs), "></template>"]
        parts = [parts, binary_part(html, at, from - at), marker]
        {parts, Map.put(noscripts, id, :binary.part(html, content)), to}
      end)
      |> then(fn {parts, noscripts, at} ->
        {IO.iodata_to_binary([parts, binary_part(html, at, byte_size(html) - at)]), noscripts}
      end)
    else
      {html, %{}}
    end
  end

  # Byte for byte, so positions in it are positions in `html`.
  defp ascii_downcase(html), do: for(<<c <- html>>, into: <<>>, do: <<if(c in ?A..?Z, do: c + 32, else: c)>>)

  # The data state: text and tags. `acc` holds each noscript found, as
  # `{from, to, attrs, content}`: where it starts and ends, and its
  # attributes and content as `{start, length}`.
  defp data(s, at, acc) do
    case :binary.match(s, "<", scope: {at, byte_size(s) - at}) do
      :nomatch -> acc
      {lt, 1} -> markup(s, lt, acc)
    end
  end

  defp markup(s, lt, acc) do
    case byte(s, lt + 1) do
      ?! -> data(s, declaration_end(s, lt + 2), acc)
      ?? -> data(s, bogus_comment_end(s, lt + 2), acc)
      ?/ -> data(s, end_tag_end(s, lt + 2), acc)
      c when c in ?a..?z -> start_tag(s, lt, acc)
      _ -> data(s, lt + 1, acc)
    end
  end

  defp start_tag(s, lt, acc) do
    name_end = name_end(s, lt + 1)

    case {tag_name(s, lt + 1), attrs(s, name_end)} do
      {_, :eof} ->
        acc

      {"noscript", {:ok, tag_end, _}} ->
        {content_end, to} = text_end(s, tag_end, "noscript")
        noscript = {lt, to, {name_end, tag_end - 1 - name_end}, {tag_end, content_end - tag_end}}
        data(s, to, [noscript | acc])

      {"script", {:ok, tag_end, _}} ->
        data(s, script_end(s, tag_end), acc)

      {"plaintext", _} ->
        acc

      {name, {:ok, tag_end, self_closing}} when name in ~w(svg math) and not self_closing ->
        foreign(s, tag_end, name, 0, acc)

      {name, {:ok, tag_end, _}} when name in @text_elements ->
        {_, to} = text_end(s, tag_end, name)
        data(s, to, acc)

      {_, {:ok, tag_end, _}} ->
        data(s, tag_end, acc)
    end
  end

  # Inside `<svg>` or `<math>` until its end tag: tags without text
  # elements, CDATA sections, and no masking.
  defp foreign(s, at, root, depth, acc) do
    case :binary.match(s, "<", scope: {at, byte_size(s) - at}) do
      :nomatch -> acc
      {lt, 1} -> s |> foreign_markup(lt, root, depth) |> foreign_next(s, root, acc)
    end
  end

  defp foreign_next({:foreign, at, depth}, s, root, acc), do: foreign(s, at, root, depth, acc)
  defp foreign_next({:data, at}, s, _root, acc), do: data(s, at, acc)
  defp foreign_next(:eof, _s, _root, acc), do: acc

  defp foreign_markup(s, lt, root, depth) do
    case byte(s, lt + 1) do
      ?! -> {:foreign, foreign_declaration_end(s, lt + 2), depth}
      ?? -> {:foreign, bogus_comment_end(s, lt + 2), depth}
      ?/ -> foreign_end_tag(s, lt + 2, root, depth)
      c when c in ?a..?z -> foreign_start_tag(s, lt + 1, root, depth)
      _ -> {:foreign, lt + 1, depth}
    end
  end

  defp foreign_declaration_end(s, at) do
    if prefix?(s, at, "[cdata["), do: match_end(s, at + 7, ["]]>"]), else: declaration_end(s, at)
  end

  defp foreign_end_tag(s, at, root, depth) do
    tag_end = end_tag_end(s, at)

    cond do
      tag_name(s, at) != root -> {:foreign, tag_end, depth}
      depth == 0 -> {:data, tag_end}
      true -> {:foreign, tag_end, depth - 1}
    end
  end

  defp foreign_start_tag(s, at, root, depth) do
    case attrs(s, name_end(s, at)) do
      :eof -> :eof
      {:ok, tag_end, false} -> {:foreign, tag_end, if(tag_name(s, at) == root, do: depth + 1, else: depth)}
      {:ok, tag_end, true} -> {:foreign, tag_end, depth}
    end
  end

  # After `<!`: a comment, or a bogus comment (a doctype ends where one does).
  defp declaration_end(s, at) do
    cond do
      not prefix?(s, at, "--") -> bogus_comment_end(s, at)
      byte(s, at + 2) == ?> -> at + 3
      prefix?(s, at + 2, "->") -> at + 4
      true -> match_end(s, at + 2, ["-->", "--!>"])
    end
  end

  defp bogus_comment_end(s, at), do: match_end(s, at, [">"])

  # After `</`: an end tag, `</>`, or a bogus comment.
  defp end_tag_end(s, at) do
    case byte(s, at) do
      nil ->
        at

      ?> ->
        at + 1

      c when c in ?a..?z ->
        case attrs(s, name_end(s, at)) do
          {:ok, at, _} -> at
          :eof -> byte_size(s)
        end

      _ ->
        bogus_comment_end(s, at)
    end
  end

  # The text of a raw text or RCDATA element: where its end tag starts and
  # where it ends, or the end of the input for both.
  defp text_end(s, at, name) do
    case end_tag_start(s, at, "</" <> name) do
      nil -> {byte_size(s), byte_size(s)}
      start -> {start, end_tag_end(s, start + 2)}
    end
  end

  defp end_tag_start(s, at, end_tag) do
    case :binary.match(s, end_tag, scope: {at, byte_size(s) - at}) do
      :nomatch -> nil
      {start, length} -> if tag_name_ends?(s, start + length), do: start, else: end_tag_start(s, start + 1, end_tag)
    end
  end

  # A script's text, with its escaped (`<!--`) and double escaped
  # (`<!--<script>`) states, where `</script>` does not end it.
  defp script_end(s, at), do: script_end(s, at, :data)

  defp script_end(s, at, state) do
    case :binary.match(s, script_patterns(state), scope: {at, byte_size(s) - at}) do
      :nomatch -> byte_size(s)
      {start, length} -> script_token(s, state, start, length)
    end
  end

  defp script_patterns(:data), do: ["</script", "<!--"]
  defp script_patterns(:escaped), do: ["</script", "<script", "-->"]
  defp script_patterns(:double_escaped), do: ["</script", "-->"]

  # `<!--` and then `>`, with any dashes, leaves the escape at once.
  defp script_token(s, :data, start, 4) do
    dashes_end = skip_dashes(s, start + 4)
    if byte(s, dashes_end) == ?>, do: script_end(s, dashes_end + 1, :data), else: script_end(s, dashes_end, :escaped)
  end

  defp script_token(s, _state, start, 3), do: script_end(s, start + 3, :data)

  defp script_token(s, state, start, length) do
    cond do
      not tag_name_ends?(s, start + length) -> script_end(s, start + 1, state)
      state == :escaped and length == 7 -> script_end(s, start + length + 1, :double_escaped)
      state == :double_escaped -> script_end(s, start + length + 1, :escaped)
      true -> end_tag_end(s, start + 2)
    end
  end

  defp skip_dashes(s, at), do: if(byte(s, at) == ?-, do: skip_dashes(s, at + 1), else: at)

  defp tag_name_ends?(s, at), do: byte(s, at) in [?/, ?> | @space]

  defp tag_name(s, at), do: binary_part(s, at, name_end(s, at) - at)

  defp name_end(s, at), do: if(byte(s, at) in [nil, ?/, ?> | @space], do: at, else: name_end(s, at + 1))

  # A tag's attributes, from after its name: `{:ok, after_its_gt,
  # self_closing}`, or `:eof` when the input ends inside the tag, which
  # drops it. A quote opens a value only right after `=`.
  defp attrs(s, at) do
    case byte(s, at) do
      nil -> :eof
      ?> -> {:ok, at + 1, false}
      ?/ -> self_closing(s, at + 1)
      c when c in @space -> attrs(s, at + 1)
      _ -> attr_name(s, at + 1)
    end
  end

  defp self_closing(s, at) do
    case byte(s, at) do
      nil -> :eof
      ?> -> {:ok, at + 1, true}
      _ -> attrs(s, at)
    end
  end

  defp attr_name(s, at) do
    case byte(s, at) do
      nil -> :eof
      ?= -> attr_value(s, at + 1)
      c when c in @space -> after_attr_name(s, at + 1)
      c when c in [?/, ?>] -> attrs(s, at)
      _ -> attr_name(s, at + 1)
    end
  end

  defp after_attr_name(s, at) do
    case byte(s, at) do
      ?= -> attr_value(s, at + 1)
      c when c in @space -> after_attr_name(s, at + 1)
      _ -> attrs(s, at)
    end
  end

  defp attr_value(s, at) do
    case byte(s, at) do
      nil ->
        :eof

      c when c in @space ->
        attr_value(s, at + 1)

      quote when quote in [?", ?'] ->
        case :binary.match(s, <<quote>>, scope: {at + 1, byte_size(s) - at - 1}) do
          :nomatch -> :eof
          {close, 1} -> attrs(s, close + 1)
        end

      ?> ->
        {:ok, at + 1, false}

      _ ->
        unquoted_value(s, at + 1)
    end
  end

  defp unquoted_value(s, at) do
    case byte(s, at) do
      nil -> :eof
      ?> -> {:ok, at + 1, false}
      c when c in @space -> attrs(s, at + 1)
      _ -> unquoted_value(s, at + 1)
    end
  end

  defp match_end(s, at, patterns) do
    case :binary.match(s, patterns, scope: {at, max(byte_size(s) - at, 0)}) do
      :nomatch -> byte_size(s)
      {start, length} -> start + length
    end
  end

  defp prefix?(s, at, prefix),
    do: byte_size(s) - at >= byte_size(prefix) and binary_part(s, at, byte_size(prefix)) == prefix

  defp byte(s, at) when at < byte_size(s), do: :binary.at(s, at)
  defp byte(_s, _at), do: nil

  defp restore_noscripts(nodes, noscripts) when noscripts == %{}, do: nodes

  # Only an empty template whose marker comes first and carries this call's
  # value is a noscript; any other template is left as it is.
  defp restore_noscripts(nodes, noscripts) do
    map(nodes, fn
      {"template", [{@noscript_attr, id} | attrs], []} = node ->
        case Map.fetch(noscripts, id) do
          {:ok, content} -> {"noscript", attrs, parse_fragment(content)}
          :error -> node
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
