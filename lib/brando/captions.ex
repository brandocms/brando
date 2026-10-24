defmodule Brando.Captions do
  @moduledoc """
  Caption text for gallery placements.

  A caption written for one placement (a gallery object's `config["title"]`, a
  video's `config["caption"]`, a gallery block override's `title`/`caption`) is
  rich text. A media record's own title is plain text and has to be escaped
  before it goes into markup — except rows written when the library title was
  itself rich text, which already hold markup and are sanitized instead.
  """

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
  def text(text) when is_binary(text) do
    case Floki.parse_fragment(text) do
      {:ok, nodes} -> nodes |> nodes_text() |> one_line()
      _ -> one_line(text)
    end
  end

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

  @doc "Markup for a plain library text: escaped, or sanitized when it already holds markup."
  def library_html(text) do
    cond do
      not is_binary(text) or String.trim(text) == "" -> nil
      markup?(text) -> if present?(text), do: HtmlSanitizeEx.basic_html(text)
      true -> text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

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

  # The markup the rich-text caption editor makes, which a rich-text library
  # title would have held too. Anything else that looks like a tag is text.
  @markup_tags ~w(p br em strong b i u a span sub sup h1 h2 h3 h4 h5 h6 ul ol li blockquote)

  defp markup?(text) do
    case Floki.parse_fragment(text) do
      {:ok, nodes} -> nodes |> Floki.find(Enum.join(@markup_tags, ",")) |> Enum.any?()
      _ -> false
    end
  end
end
