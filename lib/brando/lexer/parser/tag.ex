defmodule Brando.Lexer.Parser.Tag do
  @moduledoc false

  import NimbleParsec

  alias Brando.Lexer.Parser.Literal
  alias Brando.Lexer.Parser.Tag.ControlFlow
  alias Brando.Lexer.Parser.Tag.Iteration

  def open_tag(combinator \\ empty()) do
    combinator
    |> string("{%")
    |> Literal.whitespace()
  end

  def close_tag(combinator \\ empty()) do
    combinator
    |> Literal.whitespace()
    |> string("%}")
  end

  @spec tag_directive(NimbleParsec.t(), String.t()) :: NimbleParsec.t()
  def tag_directive(combinator \\ empty(), name) do
    combinator
    |> open_tag()
    |> string(name)
    |> close_tag()
  end

  @spec comment_tag(NimbleParsec.t()) :: NimbleParsec.t()
  def comment_tag(combinator \\ empty()) do
    combinator
    |> ignore(tag_directive("comment"))
    |> ignore(parsec(:document))
    |> ignore(tag_directive("endcomment"))
  end

  @spec tag(NimbleParsec.t()) :: NimbleParsec.t()
  def tag(combinator \\ empty()) do
    control_flow_tags =
      ControlFlow.if_expression()
      |> tag(:control_flow)

    iteration_tags =
      choice([
        Iteration.for_expression(),
        Iteration.break_tag(),
        Iteration.continue_tag()
      ])
      |> tag(:iteration)

    combinator
    |> choice([
      control_flow_tags,
      iteration_tags,
      comment_tag()
    ])
  end
end
