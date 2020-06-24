defmodule Brando.Lexer.Render.ObjectTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Brando.Lexer
  alias Brando.Lexer.Context
  alias Brando.Lexer.Parser

  describe "parse" do
    test "pa" do
      assert Lexer.parse("${entry:title}") ===
               {:ok, [object: [field: [key: "entry", key: "title"], filters: []]]}
    end
  end

  describe "render" do
    test "simple objects" do
      assert "5" == render("${ 5 }") |> to_string()
      assert "Hello" == render("${ 'Hello' }") |> to_string()
      assert "true" == render("${ true }") |> to_string()
      assert "" == render("${ nil }") |> to_string()
    end

    test "simple fields" do
      context =
        Context.new(%{
          a: "hello",
          b: %{c: 1}
        })

      assert "hello" == render("${ a }", context) |> to_string()
      assert "1" == render("${ b:c }", context) |> to_string()
    end
  end

  describe "render with filter" do
    test "abs" do
      assert "5" == render("${ -5 | abs }") |> to_string()
      assert "5" == render("${ -5 | abs | abs }") |> to_string()
    end
  end

  describe "objects" do
    test "entry" do
      context =
        Context.new(%{
          entry: %{
            title: "A Brilliant Title"
          }
        })

      assert render(
               """
               The title: ${entry:title}
               """,
               context
             )
             |> to_string()
             |> String.trim() == "The title: A Brilliant Title"
    end
  end

  describe "__" do
    test "if" do
      context =
        Context.new(%{
          entry: %{
            title: "A Brilliant Title"
          }
        })

      require Logger
      Logger.error(inspect(context, pretty: true))

      assert render(
               """
               {% if entry:title == "A Brilliant Title" %}
               The title: ${entry:title}
               {% endif %}
               """,
               context
             )
             |> to_string()
             |> String.trim() == "The title: A Brilliant Title"

      assert render(
               """
               {% if entry:title == "A New Title" %}
               The title: ${entry:title}
               {% else %}
               The new title: ${entry:title}
               {% endif %}
               """,
               context
             )
             |> to_string()
             |> String.trim() == "The new title: A Brilliant Title"
    end

    test "for" do
      context =
        Context.new(%{
          entry: %{
            books: [
              %{id: 1, title: "Title 1"},
              %{id: 2, title: "Title 2"},
              %{id: 3, title: "Title 3"}
            ]
          }
        })

      assert render(
               """
               {% for book <- entry:books %}
                 Book #${book:id} - ${book:title}
               {% endfor %}
               """,
               context
             )
             |> to_string()
             |> String.trim() == "Book #1 - Title 1\n\n  Book #2 - Title 2\n\n  Book #3 - Title 3"
    end
  end

  def render(doc, context \\ %Context{}) do
    {:ok, parsed_doc, _, _, _, _} = Parser.parse(doc)

    {result, _} = Brando.Lexer.render(parsed_doc, context)

    result
  end
end
