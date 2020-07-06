defmodule Brando.Lexer.Parser.TagTest do
  use ExUnit.Case, async: true
  import Brando.Lexer.TestHelpers

  test "parses comment" do
    assert_parse("Hello {% comment %}Ignored text{% endcomment %} World",
      text: "Hello ",
      text: " World"
    )
  end
end
