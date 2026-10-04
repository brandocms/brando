defmodule Brando.Captions do
  @moduledoc """
  Caption text for gallery placements.

  A caption written for one placement (a gallery object's `config["title"]`, a
  video's `config["caption"]`, a gallery block override's `title`/`caption`) is
  rich text. A media record's own title is plain text and has to be escaped
  before it goes into markup — except rows written when the library title was
  itself rich text, which already hold markup and are sanitized instead.
  """

  @empty_paragraph ~r{<p>\s*(<br\s*/?>)?\s*</p>}

  @doc """
  Whether `text` holds anything. An empty rich-text document serializes to
  `<p></p>`, which counts as empty.
  """
  def present?(text) when is_binary(text),
    do: text |> String.replace(@empty_paragraph, "") |> String.trim() != ""

  def present?(_text), do: false

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
      not present?(text) -> nil
      markup?(text) -> HtmlSanitizeEx.basic_html(text)
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

  # Text formatting a rich-text library title would have held. Anything else
  # that looks like a tag is text to escape.
  @markup_tags ~w(p br em strong b i u a span sub sup)

  defp markup?(text) do
    case Floki.parse_fragment(text) do
      {:ok, nodes} -> nodes |> Floki.find(Enum.join(@markup_tags, ",")) |> Enum.any?()
      _ -> false
    end
  end
end
