defmodule Brando.Villain.Tags.Picture do
  @moduledoc """
  {% picture entry.cover {
    sizes: 'auto',
    lazyload: true,
    placeholder: 'dominant_color_faded',
    srcset: 'MyApp.Projects.Project:cover.default',
    prefix: '/media'
  } %}
  """
  @behaviour Liquex.Tag

  import Phoenix.Component

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:picture)

  @impl true
  def render([source: source, args: args], context) do
    {evaled_source, _context} = Liquex.Argument.eval(source, context)

    evaled_args =
      Enum.map(args, fn arg ->
        {{key, val}, _context} = Liquex.Argument.eval(arg, context)
        {String.to_existing_atom(key), val}
      end)

    assigns = %{src: evaled_source, opts: evaled_args}

    comp = ~H"""
    <Brando.HTML.Images.picture src={@src} opts={@opts} />
    """

    html = Phoenix.LiveViewTest.rendered_to_string(comp)

    {[html], context}
  end
end
