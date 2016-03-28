defmodule Brando.VillainTest do
    use ExUnit.Case, async: true

    test "parse" do
      assert Brando.Villain.parse("") == ""
      assert Brando.Villain.parse(nil) == ""
      assert Brando.Villain.parse(~s([{"type":"columns","data":[{"class":"col-md-6 six","data":[]},{"class":"col-md-6 six","data":[{"type":"markdown","data":{"text":"Markdown"}}]}]}]))
             == "<div class=\"row\"><div class=\"col-md-6 six\"></div><div class=\"col-md-6 six\"><p>Markdown</p>\n</div></div>"
      assert Brando.Villain.parse([%{"type" => "text", "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}}])
             == "<p><strong>Some</strong> text here.</p>\n"
      assert_raise FunctionClauseError, fn ->
        Brando.Villain.parse(%{"text" => "**Some** text here.", "type" => "paragraph"}) == ""
      end
    end
end
