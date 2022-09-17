defmodule Brando.Villain.Tags.Inspect do
  @moduledoc """
  {% inspect entry.cover %}
  """
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag
  import Phoenix.LiveView.Helpers

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("inspect"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :source)
    |> ignore(Literal.whitespace())
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([source: source], context) do
    evaled_source = Liquex.Argument.eval(source, context)

    assigns = %{src: evaled_source}

    comp = ~H"""
    <div class="brando-inspect">
      <code>
        <pre>
          <%= inspect @src, pretty: true %>
        </pre>
      </code>
    </div>
    """

    html = Phoenix.LiveViewTest.rendered_to_string(comp)

    {[html], context}
  end
end
