defmodule Brando.Villain.Tags.Hide do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("hide"))
    |> ignore(Literal.whitespace())
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render(_, context), do: {[""], context}
end
