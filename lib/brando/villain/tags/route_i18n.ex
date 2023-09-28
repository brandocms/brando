defmodule Brando.Villain.Tags.RouteI18n do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Field
  alias Liquex.Parser.Tag

  alias Brando.I18n

  # {% route_i18n entry.language page_path list %}
  # {% route_i18n entry.language page_path detail { entry.uri } %}

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("route_i18n"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :locale)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :function)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :action)
    |> ignore(Literal.whitespace())
    |> optional(tag(braced_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([locale: locale, function: function, action: action, args: args], context) do
    evaled_locale = Liquex.Argument.eval(locale, context)
    evaled_args = prepare_args(args, context, function, action)

    rendered_route =
      if function == "page_path" do
        # never localize the page path. it should live as a root route that passes on its prefix as language
        apply(Brando.helpers(), :"#{function}", [Brando.endpoint(), :"#{action}"] ++ evaled_args)
      else
        I18n.Helpers.localized_path(
          evaled_locale,
          :"#{function}",
          [Brando.endpoint(), :"#{action}"] ++ evaled_args
        )
      end

    {[rendered_route], context}
  end

  def render([locale: locale, function: function, action: action], context) do
    evaled_locale = Liquex.Argument.eval(locale, context)

    rendered_route =
      if function == "page_path" do
        # never localize the page path. it should live as a root route that passes on its prefix as language
        apply(Brando.helpers(), :"#{function}", [Brando.endpoint(), :"#{action}"])
      else
        I18n.Helpers.localized_path(
          evaled_locale,
          :"#{function}",
          [Brando.endpoint(), :"#{action}"]
        )
      end

    {[rendered_route], context}
  end

  defp prepare_args(args, context, function, action) do
    evaled_args =
      args
      |> Enum.map(&Liquex.Argument.eval(&1, context))
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
