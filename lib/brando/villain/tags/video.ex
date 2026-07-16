defmodule Brando.Villain.Tags.Video do
  @moduledoc """
  {% video entry.video { autoplay: true } %}
  """
  @behaviour Liquex.Tag

  import Phoenix.Component

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:video)

  @impl true
  def render([source: source, args: args], context) do
    allowed_atoms = [
      :aspect_ratio,
      :autoplay,
      :controls,
      :loop,
      :muted,
      :playsinline,
      :preload,
      :poster,
      :width,
      :height
    ]

    # Force load them
    _ = allowed_atoms

    {evaled_source, _context} = Liquex.Argument.eval(source, context)

    evaled_args =
      args
      |> Enum.map(fn arg ->
        {{key, val}, _context} = Liquex.Argument.eval(arg, context)
        {String.to_existing_atom(key), val}
      end)

    assigns = %{video: evaled_source, opts: evaled_args}

    comp = ~H"""
    <Brando.HTML.Video.video video={@video} opts={@opts} />
    """

    html = Phoenix.LiveViewTest.rendered_to_string(comp)

    {[html], context}
  end
end
