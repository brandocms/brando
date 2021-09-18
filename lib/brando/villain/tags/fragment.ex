defmodule Brando.Villain.Tags.Fragment do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag
  alias Brando.Pages

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("fragment"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :parent_key)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :key)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :language)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([parent_key: parent_key, key: key, language: language], context) do
    {:ok, fragment} =
      Pages.get_fragment(%{matches: %{parent_key: parent_key, key: key, language: language}})

    {[fragment.html], context}
  end
end
