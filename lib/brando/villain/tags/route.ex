defmodule Brando.Villain.Tags.Route do
  @moduledoc """
  {% route page_path show entry.uri %}
  """

  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("route"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :function)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :action)
    |> ignore(Literal.whitespace())
    |> optional(tag(braced_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([function: function, action: action, args: args], context) do
    evaled_args = Enum.map(args, &Liquex.Argument.eval(&1, context))

    evaled_args =
      if function == "page_path" and action == "show", do: [evaled_args], else: evaled_args

    rendered_route =
      apply(Brando.helpers(), :"#{function}", [Brando.endpoint(), :"#{action}"] ++ evaled_args)

    {[rendered_route], context}
  end

  def render([function: function, action: action], context) do
    rendered_route = apply(Brando.helpers(), :"#{function}", [Brando.endpoint(), :"#{action}"])

    {[rendered_route], context}
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
    |> Argument.argument()
    |> repeat(
      ignore(Literal.whitespace())
      |> ignore(string(","))
      |> ignore(Literal.whitespace())
      |> concat(Argument.argument())
    )
  end
end
