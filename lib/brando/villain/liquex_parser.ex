defmodule Brando.Villain.LiquexParser do
  @moduledoc false
  import NimbleParsec

  defcombinatorp(:document, repeat(Brando.Villain.Tags.Base.base_element()))
  defparsec(:parse, parsec(:document) |> eos())
end
