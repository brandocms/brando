defmodule Brando.Lexer.Parser.Tag do
  @moduledoc false

  import NimbleParsec

  alias Brando.Lexer.Parser.Literal

  alias Brando.Lexer.Parser.Tag.{
    ControlFlow,
    Iteration,
    Variable
  }

  def open_tag(combinator \\ empty()) do
    combinator
    |> string("{%")
    # |> optional(string("-"))
    |> Literal.whitespace()
  end

  def close_tag(combinator \\ empty()) do
    combinator
    |> Literal.whitespace()
    |> string("%}")

    # |> choice([close_tag_remove_whitespace(), string("%}")])
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
        # Iteration.cycle_tag(),
        Iteration.break_tag(),
        Iteration.continue_tag()
        # Iteration.tablerow_tag()
      ])
      |> tag(:iteration)

    # variable_tags =
    #   choice([
    #     Variable.assign_tag(),
    #     Variable.capture_tag(),
    #     Variable.incrementer_tag()
    #   ])
    #   |> tag(:variable)

    combinator
    |> choice([
      control_flow_tags,
      iteration_tags,
      # variable_tags,
      comment_tag()
    ])
  end

  # Close tag that also removes the whitespace after it
  defp close_tag_remove_whitespace(combinator \\ empty()) do
    combinator
    |> string("-%}")
    |> Literal.whitespace()
  end
end
