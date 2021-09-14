defmodule Brando.Villain.LiquexParser do
  @moduledoc false
  # parsec:Brando.Villain.LiquexParser
  import NimbleParsec

  defcombinatorp(:document, repeat(Brando.Villain.Tags.Base.base_element()))
  defparsec(:parse, parsec(:document) |> eos())
  # parsec:Brando.Villain.LiquexParser
end
