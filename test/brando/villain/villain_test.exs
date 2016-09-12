defmodule Brando.VillainTest do
  defmodule OtherParser do
    @behaviour Brando.Villain.Parser

    def text(%{"text" => _, "type" => _}) do
      "other parser"
    end

    def map(_), do: nil
    def blockquote(_), do: nil
    def columns(_), do: nil
    def divider(_), do: nil
    def header(_), do: nil
    def image(_), do: nil
    def list(_), do: nil
    def slideshow(_), do: nil
    def video(_), do: nil
  end

  use ExUnit.Case, async: true

  @parser_mod Brando.Villain.Parser.Default

  test "parse" do

    assert Brando.Villain.parse("", @parser_mod) == ""
    assert Brando.Villain.parse(nil, @parser_mod) == ""
    assert Brando.Villain.parse(~s([{"type":"columns","data":[{"class":"col-md-6 six","data":[]},{"class":"col-md-6 six","data":[{"type":"markdown","data":{"text":"Markdown"}}]}]}]), @parser_mod)
           == "<div class=\"row\"><div class=\"col-md-6 six\"></div><div class=\"col-md-6 six\"><p>Markdown</p>\n</div></div>"
    assert Brando.Villain.parse([%{"type" => "text", "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}}], @parser_mod)
           == "<p><strong>Some</strong> text here.</p>\n"
    assert_raise FunctionClauseError, fn ->
      Brando.Villain.parse(%{"text" => "**Some** text here.", "type" => "paragraph"}, @parser_mod) == ""
    end

    assert Brando.Villain.parse([%{"type" => "text", "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}}], Brando.VillainTest.OtherParser) == "other parser"

    assert_raise UndefinedFunctionError, fn ->
      Brando.Villain.parse([%{"type" => "text", "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}}], Brando.VillainTest.NoneParser) == "other parser"
    end
  end
end
