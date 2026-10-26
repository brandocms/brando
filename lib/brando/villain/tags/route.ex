defmodule Brando.Villain.Tags.Route do
  @moduledoc """
  {% route page_path show entry.uri %}
  """

  @behaviour Liquex.Tag

  import NimbleParsec
  alias Brando.Villain.LiquexParser.TagGrammar
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal

  @impl true
  def parse, do: TagGrammar.parse(:route)

  # The helper and action come from template text, so they must name ones
  # that exist: an atom made from it would never be freed.
  @impl true
  def render([function: function, action: action, args: args], context) do
    evaled_args = Enum.map(args, fn arg -> Liquex.Argument.eval(arg, context) |> elem(0) end)

    evaled_args =
      if function == "page_path" and action == "show", do: [evaled_args], else: evaled_args

    rendered_route =
      apply(
        Brando.helpers(),
        existing_name(function),
        [Brando.endpoint(), existing_name(action)] ++ evaled_args
      )

    {[rendered_route], context}
  end

  def render([function: function, action: action], context) do
    rendered_route =
      apply(Brando.helpers(), existing_name(function), [Brando.endpoint(), existing_name(action)])

    {[rendered_route], context}
  end

  @doc false
  # Loaded first: until the helpers module is (in dev, on first use), the
  # names it defines need not be atoms yet.
  def existing_name(name) do
    Code.ensure_loaded(Brando.helpers())
    String.to_existing_atom(name)
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
