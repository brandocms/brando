defmodule Brando.Villain.Tags.Inspect do
  @moduledoc """
  {% inspect entry.cover %}
  """
  @behaviour Liquex.Tag

  import Phoenix.Component

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:inspect_tag)

  @impl true
  def render([source: source], context) do
    {evaled_source, _context} = Liquex.Argument.eval(source, context)

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
