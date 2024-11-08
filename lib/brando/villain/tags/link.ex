defmodule Brando.Villain.Tags.Link do
  @moduledoc """
  {% link variable_link %}
  """
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("link"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :link)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([link: link], context) do
    evaled_link = Liquex.Argument.eval(link, context)

    link_text = Brando.Villain.Filters.link_text(evaled_link, context)
    link_url = Brando.Villain.Filters.link_url(evaled_link, context)
    new_window? = evaled_link.link_target_blank

    link_html =
      ~s(<a href="#{link_url}" class="link" #{if new_window?, do: "target=\"_blank\""}>#{link_text}</a>)

    {link_html, context}
  end
end
