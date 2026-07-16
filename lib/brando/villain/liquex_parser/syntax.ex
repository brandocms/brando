defmodule Brando.Villain.LiquexParser.Syntax do
  @moduledoc """
  Parse-only definitions for Brando's custom Liquex tags.

  Keeping grammar construction independent of tag rendering prevents the
  generated NimbleParsec parser from acquiring compile-time dependencies on
  Brando's content, media, routing, and admin modules.
  """

  import NimbleParsec

  alias Liquex.Parser.Argument
  alias Liquex.Parser.Field
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Object
  alias Liquex.Parser.Tag

  @doc "Builds the parser combinator for the `headless_ref` tag."
  def headless_ref do
    tag_with_argument("headless_ref", :ref)
  end

  @doc "Builds the parser combinator for the `inspect` tag."
  def inspect_tag do
    ignore(Tag.open_tag())
    |> ignore(string("inspect"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :source)
    |> ignore(Literal.whitespace())
    |> ignore(Tag.close_tag())
  end

  @doc "Builds the parser combinator for the `ref` tag."
  def ref do
    tag_with_argument("ref", :ref)
  end

  @doc "Builds the parser combinator for the `link` tag."
  def link do
    tag_with_argument("link", :link)
  end

  @doc "Builds the parser combinator for the `picture` tag."
  def picture do
    ignore(Tag.open_tag())
    |> ignore(string("picture"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :source)
    |> ignore(Literal.whitespace())
    |> optional(tag(picture_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @doc "Builds the parser combinator for the `video` tag."
  def video do
    ignore(Tag.open_tag())
    |> ignore(string("video"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :source)
    |> ignore(Literal.whitespace())
    |> optional(tag(video_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @doc "Builds the parser combinator for the `route` tag."
  def route do
    ignore(Tag.open_tag())
    |> ignore(string("route"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :function)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :action)
    |> ignore(Literal.whitespace())
    |> optional(tag(route_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @doc "Builds the parser combinator for the `route_i18n` tag."
  def route_i18n do
    ignore(Tag.open_tag())
    |> ignore(string("route_i18n"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :locale)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :function)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :action)
    |> ignore(Literal.whitespace())
    |> optional(tag(route_args(), :args))
    |> ignore(Tag.close_tag())
  end

  @doc "Builds the parser combinator for the `fragment` tag."
  def fragment do
    ignore(Tag.open_tag())
    |> ignore(string("fragment"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :parent_key)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :key)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :language)
    |> ignore(Tag.close_tag())
  end

  @doc "Builds the parser combinator for the `hide` tag."
  def hide, do: empty_tag("hide")

  @doc "Builds the parser combinator for the `endhide` tag."
  def end_hide, do: empty_tag("endhide")

  @doc "Builds the parser combinator for the `t` translation tag."
  def translation do
    ignore(Tag.open_tag())
    |> ignore(string("t"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Field.identifier(), :language)
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Literal.quoted_string(), :string)
    |> ignore(Tag.close_tag())
  end

  @doc "Builds the parser combinator for the `datasource` tag."
  def datasource, do: empty_tag("datasource")

  @doc "Builds the parser combinator for the `enddatasource` tag."
  def end_datasource, do: empty_tag("enddatasource")

  defp tag_with_argument(name, key) do
    ignore(Tag.open_tag())
    |> ignore(string(name))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), key)
    |> ignore(Tag.close_tag())
  end

  defp empty_tag(name) do
    ignore(Tag.open_tag())
    |> ignore(string(name))
    |> ignore(Literal.whitespace())
    |> ignore(Tag.close_tag())
  end

  defp picture_args(combinator \\ empty()) do
    combinator
    |> ignore(string("{"))
    |> ignore(Literal.whitespace())
    |> repeat(
      lookahead_not(string("}"))
      |> Object.arguments()
    )
    |> ignore(Literal.whitespace())
    |> ignore(string("}"))
  end

  defp video_args(combinator \\ empty()) do
    combinator
    |> ignore(string("{ "))
    |> repeat(
      lookahead_not(string(" }"))
      |> Object.arguments()
    )
    |> ignore(string(" }"))
  end

  defp route_args(combinator \\ empty()) do
    combinator
    |> ignore(string("{ "))
    |> repeat(
      lookahead_not(string(" }"))
      |> argument_list()
    )
    |> ignore(string(" }"))
  end

  defp argument_list(combinator) do
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
