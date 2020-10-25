defmodule Brando.Villain.Tags.Fragment do
  import NimbleParsec
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag

  def fragment_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("fragment"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :parent_key)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :key)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :language)
    |> ignore(Tag.close_tag())
    |> tag(:fragment_tag)
  end

  def element(combinator \\ empty()) do
    # Add the `custom_tag/1` parsing function to the supported element tag list
    combinator
    |> choice([fragment_tag(), Base.base_element()])
  end
end
