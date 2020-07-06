defmodule Brando.Lexer.Parser.Tag.IterationTest do
  @moduledoc false

  use ExUnit.Case, async: true
  import Brando.Lexer.TestHelpers

  describe "for_expression" do
    test "parse for block with field" do
      "{% for i <- x %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            identifier: "i",
            collection: [field: [key: "x"]],
            parameters: [],
            contents: [text: "Hello"]
          ]
        ]
      )
    end

    test "parse for block with else" do
      "{% for i <- x %}Hello{% else %}Goodbye{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            identifier: "i",
            collection: [field: [key: "x"]],
            parameters: [],
            contents: [text: "Hello"]
          ],
          else: [contents: [text: "Goodbye"]]
        ]
      )
    end

    test "parse for block with range" do
      "{% for i <- (1..5) %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            identifier: "i",
            collection: [inclusive_range: [begin: [literal: 1], end: [literal: 5]]],
            parameters: [],
            contents: [text: "Hello"]
          ]
        ]
      )
    end

    test "parse for block with variable range" do
      "{% for i <- (1..x) %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            identifier: "i",
            collection: [inclusive_range: [{:begin, [literal: 1]}, {:end, [field: [key: "x"]]}]],
            parameters: [],
            contents: [text: "Hello"]
          ]
        ]
      )
    end

    test "parse for block with reversed" do
      "{% for i <- x reversed %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            {:identifier, "i"},
            {:collection, [field: [key: "x"]]},
            {:parameters, [order: :reversed]},
            {:contents, [text: "Hello"]}
          ]
        ]
      )
    end

    test "parse for block with limit" do
      "{% for i <- x limit:2 %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            {:identifier, "i"},
            {:collection, [field: [key: "x"]]},
            {:parameters, [limit: 2]},
            {:contents, [text: "Hello"]}
          ]
        ]
      )
    end

    test "parse for block with offset" do
      "{% for i <- x offset:1 %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            {:identifier, "i"},
            {:collection, [field: [key: "x"]]},
            {:parameters, [offset: 1]},
            {:contents, [text: "Hello"]}
          ]
        ]
      )
    end

    test "parse for block with reverse, limit, and offset" do
      "{% for i <- x reversed limit:2 offset:1 %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            identifier: "i",
            collection: [field: [key: "x"]],
            parameters: [order: :reversed, limit: 2, offset: 1],
            contents: [text: "Hello"]
          ]
        ]
      )
    end
  end

  describe "continue_tag" do
    test "basic continue" do
      "{% for i <- x %}{% if i == 2 %}{% continue %}{% endif %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            identifier: "i",
            collection: [field: [key: "x"]],
            parameters: [],
            contents: [
              {
                :control_flow,
                [
                  if: [
                    expression: [[left: [field: [key: "i"]], op: :==, right: [literal: 2]]],
                    contents: [iteration: [:continue]]
                  ]
                ]
              },
              {:text, "Hello"}
            ]
          ]
        ]
      )
    end
  end

  describe "break_tag" do
    test "basic continue" do
      "{% for i <- x %}{% if i == 2 %}{% break %}{% endif %}Hello{% endfor %}"
      |> assert_parse(
        iteration: [
          for: [
            identifier: "i",
            collection: [field: [key: "x"]],
            parameters: [],
            contents: [
              {
                :control_flow,
                [
                  if: [
                    expression: [[left: [field: [key: "i"]], op: :==, right: [literal: 2]]],
                    contents: [iteration: [:break]]
                  ]
                ]
              },
              {:text, "Hello"}
            ]
          ]
        ]
      )
    end
  end
end
