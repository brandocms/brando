defmodule Brando.Villain.Tags.EndHide do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("endhide"))
    |> ignore(Literal.whitespace())
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render(_, context), do: {[""], context}
end
