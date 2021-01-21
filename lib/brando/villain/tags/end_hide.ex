defmodule Brando.Villain.Tags.EndHide do
  import NimbleParsec
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  def end_hide_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("endhide"))
    |> ignore(Literal.whitespace())
    |> ignore(Tag.close_tag())

    # |> tag(:end_hide_tag)
  end

  def element(combinator \\ empty()) do
    # Add the `custom_tag/1` parsing function to the supported element tag list
    combinator
    |> choice([end_hide_tag(), Base.base_element()])
  end
end
