defmodule Brando.Villain.Tags.RenderPalette do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("render_palette"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :palette)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([palette: _palette], context) do
    palette_html = "<!-- TODO -->"
    {palette_html, context}
  end
end
