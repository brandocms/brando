defmodule Brando.Captions do
  @moduledoc """
  Caption text for gallery placements.

  A caption written for one placement (a gallery object's `config["title"]`, a
  video's `config["caption"]`, a gallery block override's `title`/`caption`) is
  rich text. A media record's own title is plain text and has to be escaped
  before it goes into markup — except rows written when the library title was
  itself rich text, which already hold markup and are sanitized instead.
  """
  alias Brando.HTML.Tree

  # The markup the rich-text caption editor makes, which a rich-text library
  # title would have held too. Anything else that looks like a tag is text.
  @markup_tags ~w(p br em strong b i u a span sub sup h1 h2 h3 h4 h5 h6 ul ol li blockquote)

  @doc """
  Whether `text` holds any text. An emptied rich-text document is markup
  without text (`<p></p>`, `<p style="text-align: center;"><br></p>`,
  `<p>&nbsp;</p>`), which counts as empty. Text without the editor's markup
  is plain, and only blank when it is whitespace: `<untitled>` is a title.
  """
  def present?(text) when is_binary(text) do
    if markup?(text), do: text(text) != nil, else: String.trim(text) != ""
  end

  def present?(_text), do: false

  # Elements that end a line of text: their text is kept apart from the next.
  @block_tags ~w(p div br h1 h2 h3 h4 h5 h6 li ul ol blockquote pre hr tr td th dt dd figcaption)

  @doc """
  A caption's text, entities decoded, on one line: blocks and line breaks
  are a space apart, inline formatting joins what it splits. `nil` when
  there is no text.
  """
  def text(text) when is_binary(text), do: text |> Tree.parse_fragment() |> nodes_text() |> one_line()

  def text(_text), do: nil

  defp one_line(text) do
    case String.split(text, ~r/\s+/u, trim: true) do
      [] -> nil
      words -> Enum.join(words, " ")
    end
  end

  defp nodes_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &nodes_text/1)
  defp nodes_text(text) when is_binary(text), do: text
  defp nodes_text({tag, _attrs, _children}) when tag in ["script", "style"], do: ""
  defp nodes_text({tag, _attrs, children}) when tag in @block_tags, do: " " <> nodes_text(children) <> " "
  defp nodes_text({_tag, _attrs, children}), do: nodes_text(children)
  defp nodes_text(_other), do: ""

  @doc """
  A rich-text caption as it is stored: `nil` when empty, and stripped to basic
  markup when it carries anything `Brando.RichText.safe_html?/1` refuses.
  """
  def normalize(text) do
    cond do
      not present?(text) -> nil
      Brando.RichText.safe_html?(text) -> text
      true -> HtmlSanitizeEx.basic_html(text)
    end
  end

  @doc """
  Markup for a plain library text: escaped, or, when it already holds the
  caption editor's markup, that markup with only the elements and attributes
  the editor makes. Its braces are entities, so the entry's Liquid pass leaves a title
  imported from a video provider as text.
  """
  def library_html(text) do
    cond do
      not is_binary(text) or String.trim(text) == "" ->
        nil

      markup?(text) ->
        if present?(text), do: text |> editor_markup() |> Brando.Villain.InertLiquid.encode()

      # Escaped once: a legacy caption's `&amp;` is the `&` it stands for
      true ->
        text
        |> HtmlEntities.decode()
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()
        |> Brando.Villain.InertLiquid.encode()
    end
  end

  @doc """
  Markup for a picture's title, which is either the placement's rich-text
  caption or the image's plain title: rich text as `normalize/1` stores it,
  plain text escaped (`library_html/1`). `nil` when there is no text. Its
  braces are entities either way: Liquid in a caption is text.
  """
  def caption_html(text) do
    if rich?(text), do: rich_html(text), else: library_html(text)
  end

  @doc """
  Whether a picture's title is rich text, which `caption_html/1` prints as
  its markup, and not plain text, which it escapes.
  """
  def rich?(text), do: is_binary(text) and markup?(text)

  @doc """
  Markup for a placement's rich-text caption: as `normalize/1` stores it,
  with only the elements and attributes the caption editor makes, and its
  braces as entities, so the entry's Liquid pass leaves it as text.
  """
  def rich_html(text), do: text |> normalize() |> editor_markup() |> Brando.Villain.InertLiquid.encode_all()

  # Only the elements the rich-text editor makes in a caption, and on them only
  # the attributes it gives them: a link's address when rich text allows it,
  # its target, `rel`, class and identifier; a paragraph's or heading's class
  # and alignment; a span's class, colour and jump-anchor id; a footnote's uid;
  # the number an ordered list starts at.
  # Any other element is left out and its text kept as text, the content of a
  # `script` or `style` too.
  defp editor_markup(nil), do: nil

  defp editor_markup(html) when is_binary(html) do
    html
    |> Tree.parse_fragment()
    |> Tree.map(&editor_node/1)
    |> Tree.to_html()
  end

  defp editor_node({tag, attrs, children}) when tag in @markup_tags,
    do: {tag, Enum.filter(attrs, &editor_attribute?(tag, &1)), children}

  defp editor_node({_tag, _attrs, children}), do: children
  defp editor_node(text) when is_binary(text), do: text
  defp editor_node(_comment), do: []

  @aligned ~w(p h1 h2 h3 h4 h5 h6)
  @alignment ~r/\Atext-align: ?(left|center|right|justify);?\z/
  @color ~r/\Acolor: ?(#[0-9a-fA-F]{3,8}|rgba?\([0-9., %]+\)|[a-zA-Z]+);?\z/

  defp editor_attribute?("a", {"href", href}), do: Brando.RichText.allowed_uri?(href)
  defp editor_attribute?("a", {"target", target}), do: target in ~w(_blank _self _parent _top)
  defp editor_attribute?("a", {"data-identifier-id", id}), do: id =~ ~r/\A[0-9]+\z/
  defp editor_attribute?("a", {name, _value}), do: name in ~w(rel class)
  defp editor_attribute?(tag, {"style", style}) when tag in @aligned, do: style =~ @alignment
  defp editor_attribute?("span", {"style", style}), do: style =~ @color
  defp editor_attribute?("span", {"data-type", type}), do: type == "jump-anchor"
  defp editor_attribute?("span", {"id", _id}), do: true
  defp editor_attribute?("sup", {"data-footnote-uid", _uid}), do: true
  defp editor_attribute?("ol", {"start", start}), do: start =~ ~r/\A-?[0-9]+\z/
  defp editor_attribute?(tag, {"class", _class}), do: tag in ["span" | @aligned]
  defp editor_attribute?(_tag, _attr), do: false

  @doc "A rich-text caption reduced to basic markup, for previews in the admin."
  def preview_html(text) do
    if present?(text), do: HtmlSanitizeEx.basic_html(text)
  end

  @doc """
  The caption to preview as `Phoenix.HTML.safe()` markup: the placement's
  rich text reduced to basic markup, else the escaped library text, else `nil`.
  """
  def safe_preview(override, library_text) do
    html = if present?(override), do: preview_html(override), else: library_html(library_text)
    if html, do: {:safe, html}
  end

  @doc "A caption as one line of plain text, or `nil` when there is none."
  def plain(text) when is_binary(text) do
    case text |> HtmlSanitizeEx.strip_tags() |> String.trim() do
      "" -> nil
      plain -> plain
    end
  end

  def plain(_text), do: nil

  defp markup?(text),
    do: text |> Tree.parse_fragment() |> Tree.find(&match?({tag, _, _} when tag in @markup_tags, &1)) != []
end
