defmodule Brando.Villain.Tags.RouteI18n do
  @moduledoc """
  {% route_i18n entry.language page_path show { entry.uri } %}
  """
  import NimbleParsec
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag

  def route_i18n_tag(combinator \\ empty()) do
    combinator
    |> ignore(Tag.open_tag())
    |> ignore(string("route_i18n"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Literal.argument(), :locale)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :function)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :action)
    |> ignore(Literal.whitespace())
    |> optional(tag(braced_args(), :args))
    |> ignore(Tag.close_tag())
    |> tag(:route_i18n_tag)
  end

  def braced_args(combinator \\ empty()) do
    combinator
    |> ignore(string("{ "))
    |> repeat(
      lookahead_not(string(" }"))
      |> arg_list()
    )
    |> ignore(string(" }"))
  end

  def arg_list(combinator \\ empty()) do
    combinator
    |> Literal.argument()
    |> repeat(
      ignore(Literal.whitespace())
      |> ignore(string(","))
      |> ignore(Literal.whitespace())
      |> concat(Literal.argument())
    )
  end

  def element(combinator \\ empty()) do
    # Add the `custom_tag/1` parsing function to the supported element tag list
    combinator
    |> choice([route_i18n_tag(), Base.base_element()])
  end
end
