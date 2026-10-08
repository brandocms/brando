defmodule Brando.Villain.Markdown.HTML do
  @moduledoc """
  Turns rendered block HTML into Markdown.

  Headings, paragraphs, lists, quotes, tables, code, links and images keep
  their meaning; layout wrappers (`div`, `section`, `article`, `figure`…) are
  read through, and what a reader cannot use is left out: scripts, styles,
  SVG, forms, buttons and navigation. A `<video>`, `<audio>` or `<iframe>`
  becomes a link to its source. Links and images with a path get the site's
  host, so the Markdown works away from the site.

  `<brando-markdown>` holds Markdown that is already written (a module's own
  `markdown` template, or a block slot inside an HTML template) and is passed
  through as it is.

  The Markdown is written by MDEx from a document tree, so text that looks
  like Markdown syntax is escaped rather than reinterpreted.
  """

  @skip ~w(script style noscript template svg math head meta link title button form input select textarea option
           label nav canvas object embed map area dialog)
  @blocks ~w(p h1 h2 h3 h4 h5 h6 ul ol blockquote pre hr table figure figcaption div section article main header
             footer aside details summary dl dt dd address center brando-markdown li tr)
  @render_options [extension: [table: true, strikethrough: true]]

  @doc "Markdown for `html`, without a trailing newline. Empty HTML gives `\"\"`."
  @spec to_markdown(String.t() | iodata() | nil) :: String.t()
  def to_markdown(nil), do: ""

  def to_markdown(html) do
    html = IO.iodata_to_binary(html)

    if String.trim(html) == "" do
      ""
    else
      html
      |> Floki.parse_fragment!()
      |> document()
      |> render()
    end
  end

  @doc "Markdown for a list of MDEx block nodes."
  @spec render([struct()] | MDEx.Document.t()) :: String.t()
  def render(%MDEx.Document{nodes: []}), do: ""

  def render(%MDEx.Document{} = document) do
    document
    |> MDEx.to_markdown!(@render_options)
    |> String.trim()
    # The writer escapes every `!`; only one before `[` starts an image.
    |> String.replace(~r/\\!(?!\[)/, "!")
  end

  def render(nodes) when is_list(nodes), do: render(%MDEx.Document{nodes: nodes})

  @doc "The MDEx document for parsed HTML nodes."
  @spec document(Floki.html_tree()) :: MDEx.Document.t()
  def document(tree), do: %MDEx.Document{nodes: blocks(tree)}

  # -- Blocks ------------------------------------------------------------------

  defp blocks(nodes) do
    {blocks, inline} =
      Enum.reduce(nodes, {[], []}, fn node, {blocks, inline} ->
        if block?(node) do
          {Enum.reverse(block(node), flush(inline, blocks)), []}
        else
          {blocks, Enum.reverse(inline(node), inline)}
        end
      end)

    blocks = flush(inline, blocks)
    Enum.reverse(blocks)
  end

  # Adds the inline nodes gathered so far (reversed) as a paragraph.
  defp flush(inline, blocks) do
    case inline |> Enum.reverse() |> trim_inline() do
      [] -> blocks
      nodes -> [%MDEx.Paragraph{nodes: nodes} | blocks]
    end
  end

  defp block?({tag, _attrs, _children}) when tag in @blocks, do: true
  defp block?(_node), do: false

  defp block({"p", _, children}), do: paragraph(children)

  defp block({"h" <> level, _, children}) do
    case trim_inline(Enum.flat_map(children, &inline/1)) do
      [] -> []
      nodes -> [%MDEx.Heading{level: String.to_integer(level), nodes: nodes}]
    end
  end

  defp block({tag, attrs, children}) when tag in ["ul", "ol"] do
    type = if tag == "ol", do: :ordered, else: :bullet
    start = if tag == "ol", do: attr_integer(attrs, "start", 1), else: 1

    items =
      children
      |> Enum.filter(&match?({"li", _, _}, &1))
      |> Enum.map(fn {"li", _, item} ->
        %MDEx.ListItem{list_type: type, start: start, tight: true, nodes: list_item(item)}
      end)
      |> Enum.reject(&(&1.nodes == []))

    if items == [], do: [], else: [%MDEx.List{list_type: type, start: start, tight: true, nodes: items}]
  end

  defp block({"blockquote", _, children}) do
    case blocks(children) do
      [] -> []
      nodes -> [%MDEx.BlockQuote{nodes: nodes}]
    end
  end

  defp block({"pre", _, children}) do
    case Floki.text(children) do
      "" ->
        []

      text ->
        [%MDEx.CodeBlock{literal: String.trim_trailing(text) <> "\n", fenced: true, fence_char: "`", fence_length: 3}]
    end
  end

  defp block({"hr", _, _}), do: [%MDEx.ThematicBreak{}]
  defp block({"table", _, _} = table), do: table(table)
  defp block({"figcaption", _, children}), do: caption(children)
  defp block({"brando-markdown", _, children}), do: children |> Floki.text() |> markdown_nodes()
  defp block({"tr", _, _} = row), do: table({"table", [], [row]})
  defp block({_wrapper, _, children}), do: blocks(children)

  defp paragraph(children) do
    case trim_inline(Enum.flat_map(children, &inline/1)) do
      [] -> []
      nodes -> [%MDEx.Paragraph{nodes: nodes}]
    end
  end

  # A caption reads as italic text under its image.
  defp caption(children) do
    case trim_inline(Enum.flat_map(children, &inline/1)) do
      [] -> []
      nodes -> [%MDEx.Paragraph{nodes: [%MDEx.Emph{nodes: nodes}]}]
    end
  end

  defp list_item(children) do
    if Enum.any?(children, &block?/1), do: blocks(children), else: paragraph(children)
  end

  defp markdown_nodes(markdown) do
    case String.trim(markdown) do
      "" -> []
      markdown -> MDEx.parse_document!(markdown, @render_options).nodes
    end
  end

  defp table(table) do
    rows =
      table
      |> Floki.find("tr")
      |> Enum.map(fn {"tr", _, cells} ->
        cells
        |> Enum.filter(&match?({tag, _, _} when tag in ["th", "td"], &1))
        |> Enum.map(fn {_, _, content} ->
          %MDEx.TableCell{nodes: content |> Enum.flat_map(&inline/1) |> trim_inline() |> no_breaks()}
        end)
      end)
      |> Enum.reject(&(&1 == []))

    case rows do
      [] ->
        []

      [header | _] = rows ->
        columns = rows |> Enum.map(&length/1) |> Enum.max()
        rows = Enum.map(rows, &pad_row(&1, columns))
        header_row = %MDEx.TableRow{header: true, nodes: pad_row(header, columns)}
        body = rows |> tl() |> Enum.map(&%MDEx.TableRow{nodes: &1})

        [
          %MDEx.Table{
            alignments: List.duplicate(:none, columns),
            num_columns: columns,
            num_rows: length(rows),
            nodes: [header_row | body]
          }
        ]
    end
  end

  defp pad_row(cells, columns), do: cells ++ List.duplicate(%MDEx.TableCell{}, columns - length(cells))

  defp no_breaks(nodes), do: Enum.map(nodes, &if(match?(%MDEx.LineBreak{}, &1), do: %MDEx.Text{literal: " "}, else: &1))

  # -- Inline ------------------------------------------------------------------

  defp inline(text) when is_binary(text), do: [%MDEx.Text{literal: collapse(text)}]
  defp inline({:comment, _}), do: []
  defp inline({tag, _, _}) when tag in @skip, do: []
  defp inline({tag, _, children}) when tag in ["strong", "b"], do: wrap(%MDEx.Strong{}, children)
  defp inline({tag, _, children}) when tag in ["em", "i", "cite"], do: wrap(%MDEx.Emph{}, children)
  defp inline({tag, _, children}) when tag in ["del", "s", "strike"], do: wrap(%MDEx.Strikethrough{}, children)
  defp inline({"br", _, _}), do: [%MDEx.LineBreak{}]

  defp inline({"code", _, children}) do
    case Floki.text(children) do
      "" -> []
      text -> [%MDEx.Code{literal: text, num_backticks: 1}]
    end
  end

  defp inline({"a", attrs, children}) do
    nodes = trim_inline(Enum.flat_map(children, &inline/1))

    case {link_url(attr(attrs, "href")), nodes} do
      {_, []} -> []
      {nil, nodes} -> nodes
      {url, nodes} -> [%MDEx.Link{url: url, title: "", nodes: nodes}]
    end
  end

  defp inline({"img", attrs, _}), do: image(attrs)
  defp inline({"picture", _, _} = picture), do: picture |> Floki.find("img") |> Enum.take(1) |> Enum.flat_map(&inline/1)

  defp inline({tag, attrs, children}) when tag in ["video", "audio", "iframe"] do
    source = attr(attrs, "src") || attr(attrs, "data-src") || source_src(children)

    case link_url(source) do
      nil -> []
      url -> [%MDEx.Link{url: url, title: "", nodes: [%MDEx.Text{literal: attr(attrs, "title") || url}]}]
    end
  end

  defp inline({_tag, _, children}), do: Enum.flat_map(children, &inline/1)
  defp inline(_), do: []

  defp wrap(node, children) do
    case trim_inline(Enum.flat_map(children, &inline/1)) do
      [] -> []
      nodes -> [%{node | nodes: nodes}]
    end
  end

  # Lazy-loaded images carry the real address in `data-src`; a `data:` URI is
  # only a placeholder.
  defp image(attrs) do
    src =
      ["data-src", "src", "data-ll-src"]
      |> Enum.map(&attr(attrs, &1))
      |> Enum.find(&(is_binary(&1) and &1 != "" and not String.starts_with?(&1, "data:")))

    case link_url(src) do
      nil -> []
      url -> [%MDEx.Image{url: url, title: "", nodes: [%MDEx.Text{literal: attr(attrs, "alt") || ""}]}]
    end
  end

  defp source_src(children) do
    children
    |> Floki.find("source")
    |> Enum.find_value(&(&1 |> Floki.attribute("src") |> List.first()))
  end

  @doc false
  def link_url(url) when url in [nil, ""], do: nil

  def link_url(url) do
    url = String.trim(url)

    cond do
      String.starts_with?(url, "//") -> "https:" <> url
      String.starts_with?(url, "/") -> Brando.Utils.hostname(url)
      String.starts_with?(url, ["javascript:", "data:"]) -> nil
      true -> url
    end
  end

  defp attr(attrs, name), do: Enum.find_value(attrs, fn {key, value} -> key == name && value end)

  defp attr_integer(attrs, name, default) do
    case Integer.parse(attr(attrs, name) || "") do
      {value, _} -> value
      :error -> default
    end
  end

  defp collapse(text), do: String.replace(text, ~r/\s+/u, " ")

  # Whitespace at the edges of a paragraph, and around its line breaks, is
  # the HTML's indentation rather than text.
  defp trim_inline(nodes) do
    nodes
    |> merge_text()
    |> trim_edge(:leading)
    |> Enum.reverse()
    |> trim_edge(:trailing)
    |> Enum.reverse()
  end

  defp merge_text(nodes) do
    nodes
    |> Enum.reduce([], fn
      %MDEx.Text{literal: b}, [%MDEx.Text{literal: a} | rest] -> [%MDEx.Text{literal: a <> b} | rest]
      node, acc -> [node | acc]
    end)
    |> Enum.reverse()
  end

  defp trim_edge([%MDEx.Text{literal: text} | rest], side) do
    trimmed = if side == :leading, do: String.trim_leading(text), else: String.trim_trailing(text)
    if trimmed == "", do: trim_edge(rest, side), else: [%MDEx.Text{literal: trimmed} | rest]
  end

  defp trim_edge([%MDEx.LineBreak{} | rest], side), do: trim_edge(rest, side)
  defp trim_edge(nodes, _side), do: nodes
end
