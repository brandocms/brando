defmodule Brando.Lexer.Parser.Tag.Iteration do
  @moduledoc false

  import NimbleParsec

  alias Brando.Lexer.Parser.Field
  alias Brando.Lexer.Parser.Literal
  alias Brando.Lexer.Parser.Tag
  alias Brando.Lexer.Parser.Tag.ControlFlow

  @spec for_expression(NimbleParsec.t()) :: NimbleParsec.t()
  def for_expression(combinator \\ empty()) do
    combinator
    |> for_in_tag()
    |> tag(parsec(:document), :contents)
    |> tag(:for)
    |> optional(ControlFlow.else_tag())
    |> ignore(Tag.tag_directive("endfor"))
  end

  @spec cycle_tag(NimbleParsec.t()) :: NimbleParsec.t()
  def cycle_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("cycle"))
    |> ignore(Literal.whitespace(empty(), 1))
    |> optional(cycle_group() |> unwrap_and_tag(:group))
    |> tag(argument_sequence(), :sequence)
    |> ignore(Tag.close_tag())
    |> tag(:cycle)
  end

  @spec continue_tag(NimbleParsec.t()) :: NimbleParsec.t()
  def continue_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.tag_directive("continue"))
    |> replace(:continue)
  end

  @spec break_tag(NimbleParsec.t()) :: NimbleParsec.t()
  def break_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.tag_directive("break"))
    |> replace(:break)
  end

  def tablerow_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("tablerow"))
    |> ignore(Literal.whitespace(empty(), 1))
    |> unwrap_and_tag(Field.identifier(), :identifier)
    |> ignore(Literal.whitespace(empty(), 1))
    |> ignore(string("in"))
    |> ignore(Literal.whitespace(empty(), 1))
    |> tag(collection(), :collection)
    |> ignore(Literal.whitespace())
    |> tag(tablerow_parameters(), :parameters)
    |> ignore(Tag.close_tag())
    |> tag(parsec(:document), :contents)
    |> ignore(Tag.tag_directive("endtablerow"))
    |> tag(:tablerow)
  end

  defp argument_sequence(combinator \\ empty()) do
    combinator
    |> Literal.argument()
    |> repeat(
      ignore(string(","))
      |> ignore(Literal.whitespace())
      |> Literal.argument()
    )
  end

  defp for_in_tag(combinator) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("for"))
    |> ignore(Literal.whitespace(empty(), 1))
    |> unwrap_and_tag(Field.identifier(), :identifier)
    |> ignore(Literal.whitespace(empty(), 1))
    |> ignore(string("<-"))
    |> ignore(Literal.whitespace(empty(), 1))
    |> tag(collection(), :collection)
    |> ignore(Literal.whitespace())
    |> tag(for_parameters(), :parameters)
    |> ignore(Tag.close_tag())
  end

  defp collection(combinator \\ empty()) do
    combinator
    |> choice([Literal.range(), Literal.argument()])
  end

  defp for_parameters(combinator \\ empty()) do
    combinator
    |> repeat(choice([reversed(), limit(), offset()]))
  end

  defp tablerow_parameters(combinator \\ empty()) do
    combinator
    |> repeat(choice([cols(), limit(), offset()]))
  end

  defp reversed(combinator \\ empty()) do
    combinator
    |> replace(string("reversed"), :reversed)
    |> unwrap_and_tag(:order)
    |> ignore(Literal.whitespace())
  end

  defp cols(combinator \\ empty()) do
    combinator
    |> ignore(string("cols:"))
    |> unwrap_and_tag(integer(min: 1), :cols)
    |> ignore(Literal.whitespace())
  end

  defp limit(combinator \\ empty()) do
    combinator
    |> ignore(string("limit:"))
    |> unwrap_and_tag(integer(min: 1), :limit)
    |> ignore(Literal.whitespace())
  end

  defp offset(combinator \\ empty()) do
    combinator
    |> ignore(string("offset:"))
    |> unwrap_and_tag(integer(min: 1), :offset)
    |> ignore(Literal.whitespace())
  end

  defp cycle_group(combinator \\ empty()) do
    combinator
    |> Literal.literal()
    |> ignore(string(":"))
    |> ignore(Literal.whitespace())
  end
end
