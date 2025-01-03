defmodule Brando.Villain.Tags.Video do
  @moduledoc """
  {% video entry.video { autoplay: true } %}
  """
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Object
  alias Liquex.Parser.Tag
  import Phoenix.Component

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("video"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :source)
    |> ignore(Literal.whitespace())
    |> optional(tag(braced_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([source: source, args: args], context) do
    _ = [
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

    evaled_source = Liquex.Argument.eval(source, context)

    evaled_args =
      args
      |> Enum.map(fn arg ->
        {key, val} = Liquex.Argument.eval(arg, context)
        {String.to_existing_atom(key), val}
      end)

    assigns = %{video: evaled_source, opts: evaled_args}

    comp = ~H"""
    <Brando.HTML.Video.video video={@video} opts={@opts} />
    """

    html = Phoenix.LiveViewTest.rendered_to_string(comp)

    {[html], context}
  end

  defp braced_args(combinator \\ empty()) do
    combinator
    |> ignore(string("{ "))
    |> repeat(
      lookahead_not(string(" }"))
      |> Object.arguments()
    )
    |> ignore(string(" }"))
  end
end
