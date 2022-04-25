defmodule Brando.Villain.Tags.T do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("t"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :language)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Literal.quoted_string(), :string)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([language: language, string: string], context) do
    ctx_language = Map.get(context.variables, "language")

    if language == ctx_language do
      {[string], context}
    else
      {[], context}
    end
  end
end
