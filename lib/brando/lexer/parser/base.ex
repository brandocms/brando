defmodule Brando.Lexer.Parser.Base do
  @moduledoc """
  Liquid base parser
  """

  import NimbleParsec

  alias Brando.Lexer.Parser.{
    Literal,
    Object,
    Tag
  }

  @spec base_element(NimbleParsec.t()) :: NimbleParsec.t()
  def base_element(combinator \\ empty()) do
    combinator
    |> choice([
      Object.object(),
      Tag.tag(),
      Literal.text()
    ])
  end
end
