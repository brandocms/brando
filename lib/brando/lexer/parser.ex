defmodule Brando.Lexer.Parser do
  @moduledoc """
  Liquid parser
  """

  import NimbleParsec

  alias Brando.Lexer.Parser.Base

  defcombinatorp(:document, repeat(Base.base_element()))
  defparsec(:parse, parsec(:document) |> eos())
end
