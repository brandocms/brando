defmodule Brando.Villain.Tags.T do
  @moduledoc """
  {% t no 'Norsk' %}
  """
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
    |> unwrap_and_tag(quoted_string(), :string)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([language: language, string: string], context) do
    ctx_language = Access.get(context, "language")

    if language == ctx_language do
      {[string], context}
    else
      {[], context}
    end
  end

  defp quoted_string do
    single_quote_string =
      ignore(utf8_char([?']))
      |> repeat(
        lookahead_not(ascii_char([?']))
        |> choice([string(~s{\'}), utf8_char([])])
      )
      |> ignore(utf8_char([?']))
      |> reduce({List, :to_string, []})

    double_quote_string =
      ignore(utf8_char([?"]))
      |> repeat(
        lookahead_not(ascii_char([?"]))
        |> choice([string(~s{\"}), utf8_char([])])
      )
      |> ignore(utf8_char([?"]))
      |> reduce({List, :to_string, []})

    choice([single_quote_string, double_quote_string])
  end
end
