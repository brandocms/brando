defmodule Brando.Villain.Tags.HeadlessRef do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("headless_ref"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :ref)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render(_, context) do
    {"", context}
  end
end
