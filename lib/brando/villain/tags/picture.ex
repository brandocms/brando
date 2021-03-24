defmodule Brando.Villain.Tags.Picture do
  @moduledoc """
  """
  import NimbleParsec
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag
  alias Liquex.Parser.Object

  # {% picture entry.cover { size: 'auto', lazyload: true } %}

  def picture_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("picture"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Literal.argument(), :source)
    |> ignore(Literal.whitespace())
    |> optional(tag(json_args(), :args))
    |> ignore(Tag.close_tag())
    |> tag(:picture_tag)
  end

  def json_args(combinator \\ empty()) do
    # combinator
    # |> ignore(string("{"))
    # |> ignore(Literal.whitespace())
    # |> tag(:args)
    # |> ignore(Literal.whitespace())
    # |> ignore(string("}"))

    combinator
    |> ignore(string("{ "))
    |> repeat(
      lookahead_not(string(" }"))
      |> Object.arguments()
    )
    |> ignore(string(" }"))
  end

  # def json_args(combinator \\ empty()) do
  #   combinator
  #   |> ignore(string("{"))
  #   |> ignore(Literal.whitespace())
  #   |> tag(:args)
  #   |> ignore(Literal.whitespace())
  #   |> ignore(string("}"))
  # end

  def element(combinator \\ empty()) do
    # Add the `custom_tag/1` parsing function to the supported element tag list
    combinator
    |> choice([picture_tag(), Base.base_element()])
  end
end
