defmodule Brando.Villain.Tags.Inspect do
  @moduledoc """
  {% inspect entry.cover %}
  """
  @behaviour Liquex.Tag

  import Phoenix.Component

  alias Brando.Villain.InertLiquid
  alias Brando.Villain.LiquexParser.TagGrammar
  alias Brando.Villain.TemplateView

  @impl true
  def parse, do: TagGrammar.parse(:inspect_tag)

  @impl true
  def render([source: source], context) do
    # Whole structs, printed for a developer: no credentials, and Liquid in
    # them is text to the entry's final pass.
    assigns = %{src: source |> TemplateView.eval(context) |> TemplateView.printable()}

    comp = ~H"""
    <div class="brando-inspect">
      <code>
        <pre>
          <%= inspect @src, pretty: true %>
        </pre>
      </code>
    </div>
    """

    html = comp |> Phoenix.LiveViewTest.rendered_to_string() |> InertLiquid.encode_all()

    {[html], context}
  end
end
