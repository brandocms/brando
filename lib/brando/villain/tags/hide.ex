defmodule Brando.Villain.Tags.Hide do
  import NimbleParsec
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  def hide_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("hide"))
    |> ignore(Literal.whitespace())
    |> ignore(Tag.close_tag())

    # |> tag(:hide_tag)
  end

  def element(combinator \\ empty()) do
    # Add the `custom_tag/1` parsing function to the supported element tag list
    combinator
    |> choice([hide_tag(), Base.base_element()])
  end
end
