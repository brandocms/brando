defmodule Brando.Villain.LiquexParser do
  @moduledoc false
  import NimbleParsec

  defcombinatorp(:document, repeat(Brando.Villain.Tags.Fragment.element()))
  defparsec(:parse, parsec(:document) |> eos())
end
