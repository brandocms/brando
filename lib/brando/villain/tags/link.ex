defmodule Brando.Villain.Tags.Link do
  @moduledoc """
  {% link variable_link %}
  """
  @behaviour Liquex.Tag

  alias Brando.Content.Identifier
  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:link)

  @impl true
  def render([link: link], context) do
    {evaled_link, _context} = Liquex.Argument.eval(link, context)

    link_text =
      evaled_link
      |> text(context)
      |> to_string()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    link_url = evaled_link |> Brando.Villain.Filters.link_url() |> href()
    new_window? = evaled_link.link_target_blank

    link_html =
      ~s(<a href="#{link_url}" class="link" #{if new_window?, do: "target=\"_blank\""}>#{link_text}</a>)

    {link_html, context}
  end

  # The text is plain, to escape once: an editor's label as written, or else
  # the linked entry's title, which a HEEx identifier stores escaped
  defp text(%{link_type: :identifier, link_text: nil, identifier: identifier}, _context),
    do: Identifier.title_text(identifier)

  defp text(link, _context), do: Brando.Villain.Filters.link_text(link)

  # An address with a script or unknown scheme renders as an empty href.
  defp href(url) do
    case Brando.Villain.Parser.safe_url(url) do
      nil -> ""
      url -> Brando.Villain.Parser.escape_attr(url)
    end
  end
end
