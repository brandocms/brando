defmodule Brando.Villain.Tags.RouteI18n do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal

  alias Brando.I18n
  alias Brando.Villain.LiquexParser.TagGrammar
  alias Brando.Villain.Tags.Route

  # {% route_i18n entry.language page_path list %}
  # {% route_i18n entry.language page_path detail { entry.uri } %}

  @impl true
  def parse, do: TagGrammar.parse(:route_i18n)

  # The helper and action come from template text, so they must name ones
  # that exist: an atom made from it would never be freed.
  @impl true
  def render([locale: locale, function: function, action: action, args: args], context) do
    {evaled_locale, _context} = Liquex.Argument.eval(locale, context)
    evaled_args = prepare_args(args, context, function, action)

    rendered_route =
      if function == "page_path" do
        # never localize the page path. it should live as a root route that passes on its prefix as language
        apply(
          Brando.helpers(),
          Route.existing_name(function),
          [Brando.endpoint(), Route.existing_name(action)] ++ evaled_args
        )
      else
        I18n.Helpers.localized_path(
          evaled_locale,
          function,
          [Brando.endpoint(), Route.existing_name(action)] ++ evaled_args
        )
      end

    {[rendered_route], context}
  end

  def render([locale: locale, function: function, action: action], context) do
    {evaled_locale, _context} = Liquex.Argument.eval(locale, context)

    rendered_route =
      if function == "page_path" do
        # never localize the page path. it should live as a root route that passes on its prefix as language
        apply(Brando.helpers(), Route.existing_name(function), [Brando.endpoint(), Route.existing_name(action)])
      else
        I18n.Helpers.localized_path(
          evaled_locale,
          function,
          [Brando.endpoint(), Route.existing_name(action)]
        )
      end

    {[rendered_route], context}
  end

  defp prepare_args(args, context, function, action) do
    evaled_args =
      args
      |> Enum.map(fn arg -> Liquex.Argument.eval(arg, context) |> elem(0) end)
      |> Enum.reject(&(&1 == nil))

    if function == "page_path" and action == "show" do
      Enum.map(evaled_args, &String.split(&1, "/"))
    else
      evaled_args
    end
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
