defmodule Brando.Villain.Tags.Video do
  @moduledoc """
  {% video entry.video { autoplay: true } %}
  """
  @behaviour Liquex.Tag

  import Phoenix.Component

  alias Brando.Villain.InertLiquid
  alias Brando.Villain.LiquexParser.TagGrammar
  alias Brando.Villain.TemplateView

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
      :preload,
      :poster,
      :quality,
      :width,
      :height
    ]

    # Force load them
    _ = allowed_atoms

    evaled_source = TemplateView.eval(source, context)

    evaled_args =
      args
      |> Enum.map(fn arg ->
        {key, val} = TemplateView.eval(arg, context)
        {String.to_existing_atom(key), val}
      end)

    assigns = %{video: evaled_source, opts: evaled_args}

    comp = ~H"""
    <Brando.HTML.Video.video video={@video} opts={@opts} />
    """

    # Texts an editor wrote about the media: text to the entry's final Liquid pass
    html = comp |> Phoenix.LiveViewTest.rendered_to_string() |> InertLiquid.encode()

    {[html], context}
  end
end
