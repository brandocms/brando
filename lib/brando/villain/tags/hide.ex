defmodule Brando.Villain.Tags.Hide do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag
  alias Brando.Pages

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
