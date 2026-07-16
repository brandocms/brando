defmodule Brando.Villain.Tags.Link do
  @moduledoc """
  {% link variable_link %}
  """
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:link)

  @impl true
  def render([link: link], context) do
    {evaled_link, _context} = Liquex.Argument.eval(link, context)

    link_text = Brando.Villain.Filters.link_text(evaled_link, context)
    link_url = Brando.Villain.Filters.link_url(evaled_link, context)
    new_window? = evaled_link.link_target_blank

    link_html =
      ~s(<a href="#{link_url}" class="link" #{if new_window?, do: "target=\"_blank\""}>#{link_text}</a>)

    {link_html, context}
  end
end
