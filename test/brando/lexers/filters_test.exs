defmodule Brando.Lexer.FilterTest do
  @moduledoc false

  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Lexer
  alias Brando.Lexer.Context
  alias Brando.Lexer.Parser

  describe "parsing" do
    test "date" do
      assert Lexer.parse("${entry:inserted_at|date:\"%y/%m/%d\"}") ===
               {:ok,
                [
                  object: [
                    field: [key: "entry", key: "inserted_at"],
                    filters: [{:filter, ["date", {:arguments, [literal: "%y/%m/%d"]}]}]
                  ]
                ]}
    end
  end

  describe "rendering" do
    test "date" do
      context =
        Context.new(%{
          entry: %{
            inserted_at: ~D[2020-01-01]
          }
        })

      assert render(
               """
               Entry was inserted at ${entry:inserted_at|date:"%Y-%m-%d"}
               """,
               context
             )
             |> to_string()
             |> String.trim() == "Entry was inserted at 2020-01-01"

      assert render(
               """
               Entry was inserted at ${entry:inserted_at|date}
               """,
               context
             )
             |> to_string()
             |> String.trim() == "Entry was inserted at 2020-01-01"
    end
  end

  def render(doc, context \\ %Context{}) do
    {:ok, parsed_doc, _, _, _, _} = Parser.parse(doc)
    {result, _} = Brando.Lexer.render(parsed_doc, context)
    result
  end
end
