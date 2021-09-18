defmodule Brando.Villain.Tags.Picture do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Base
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag
  alias Liquex.Parser.Object
  alias Brando.Pages

  # {% picture entry.cover { size: 'auto', lazyload: true, srcset: 'MyApp.Projects.Project:cover.regular', prefix: 'media' } %}

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("picture"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :source)
    |> ignore(Literal.whitespace())
    |> optional(tag(braced_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([source: source, args: args], context) do
    evaled_source = Liquex.Argument.eval(source, context)

    evaled_args =
      args
      |> Enum.map(fn arg ->
        {key, val} = Liquex.Argument.eval(arg, context)
        {String.to_existing_atom(key), val}
      end)

    html =
      evaled_source
      |> Brando.HTML.Images.picture_tag(evaled_args)
      |> Phoenix.HTML.safe_to_string()

    {[html], context}
  end

  defp braced_args(combinator \\ empty()) do
    combinator
    |> ignore(string("{ "))
    |> repeat(
      lookahead_not(string(" }"))
      |> Object.arguments()
    )
    |> ignore(string(" }"))
  end
end
