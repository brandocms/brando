defmodule Brando.Lexer.RenderTest do
  @moduledoc false

  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Factory
  alias Brando.Lexer
  alias Brando.Lexer.Context
  alias Brando.Lexer.Parser

  describe "parsing" do
    test "entry" do
      assert Lexer.parse("${entry:title}") ===
               {:ok, [object: [field: [key: "entry", key: "title"], filters: []]]}
    end

    test "entry deep" do
      assert Lexer.parse("${entry:creator.profile.name}") ===
               {:ok,
                [
                  object: [
                    field: [key: "entry", key: "creator", key: "profile", key: "name"],
                    filters: []
                  ]
                ]}
    end

    test "global" do
      assert Lexer.parse("${global:system.notice}") ===
               {:ok,
                [object: [field: [key: "global", key: "system", key: "notice"], filters: []]]}
    end

    test "link" do
      assert Lexer.parse("${link:instagram.url}") ===
               {:ok, [object: [field: [key: "link", key: "instagram", key: "url"], filters: []]]}
    end

    test "fragment" do
      assert Lexer.parse("${fragment:index/01_header/en}") ===
               {:ok, [object: [field: [key: "fragment", key: "index/01_header/en"], filters: []]]}
    end
  end

  describe "rendering" do
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

      assert "hello" == render("${a}", context) |> to_string()
      assert "1" == render("${b:c}", context) |> to_string()
    end

    test "abs" do
      assert "5" == render("${ -5 | abs }") |> to_string()
      assert "5" == render("${ -5 | abs | abs }") |> to_string()
    end

    test "entry" do
      context =
        Context.new(%{
          entry: %{
            title: "A Brilliant Title",
            more: %{
              stuff: "stuff to be slugged"
            }
          }
        })

      assert render(
               """
               The title: ${entry:title} - ${entry:more.stuff|slug}
               """,
               context
             )
             |> to_string()
             |> String.trim() == "The title: A Brilliant Title - stuff-to-be-slugged"
    end

    test "if" do
      context =
        Context.new(%{
          entry: %{
            title: "A Brilliant Title"
          }
        })

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

    test "fragment not found" do
      context = Context.new(%{})

      assert render(
               """
               Testing fragment:
               ${fragment:index/header/en}
               """,
               context
             )
             |> to_string()
             |> String.trim() === "Testing fragment:"

      Factory.insert(:page_fragment, parent_key: "index", key: "header", language: "en")

      assert render(
               """
               Testing fragment:
               ${fragment:index/header/en}
               """,
               context
             )
             |> to_string()
             |> String.trim() === "Testing fragment:\nfragment content!"
    end
  end

  def render(doc, context \\ %Context{}) do
    {:ok, parsed_doc, _, _, _, _} = Parser.parse(doc)

    {result, _} = Brando.Lexer.render(parsed_doc, context)

    result
  end
end
