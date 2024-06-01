defmodule Brando.Villain.Tags.Picture do
  @moduledoc """
  {% picture entry.cover { size: 'auto', lazyload: true, srcset: 'MyApp.Projects.Project:cover.default', prefix: '/media' } %}
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
    |> ignore(string("picture"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :source)
    |> ignore(Literal.whitespace())
    |> optional(tag(braced_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([source: source, args: args], context) do
    evaled_source = Liquex.Argument.eval(source, context)

    evaled_args =
      args
      |> Enum.map(fn arg ->
        {key, val} = Liquex.Argument.eval(arg, context)
        {String.to_existing_atom(key), val}
      end)

    assigns = %{src: evaled_source, opts: evaled_args}

    require Logger

    Logger.error("""

    villain/tags/picture
    #{inspect(assigns, pretty: true)}

    """)

    comp = ~H"""
    <Brando.HTML.Images.picture src={@src} opts={@opts} />
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
