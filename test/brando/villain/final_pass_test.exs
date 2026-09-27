defmodule Brando.Villain.FinalPassTest do
  use ExUnit.Case, async: true

  alias Brando.Villain
  alias Liquex.Context

  test "preserves plain HTML and whitespace while stripping editor identifiers" do
    html = "\n <p>Blåbær &amp; {one brace}</p>\n<a data-identifier-id=\"42\" href=\"/case\">Case</a> \n"

    assert Villain.parse_and_render(html, Context.new(%{})) ==
             "\n <p>Blåbær &amp; {one brace}</p>\n<a href=\"/case\">Case</a> \n"

    assert Villain.parse_and_render([], Context.new(%{})) == ""
  end

  test "evaluates output delimiters split across iodata chunks" do
    html = ["<a data-identifier-id=\"42\" href=\"/case\">", ["{", "{ title | upcase }}"], "</a>"]

    assert Villain.parse_and_render(html, Context.new(%{"title" => "Case"})) ==
             "<a href=\"/case\">CASE</a>"
  end

  test "evaluates tag-only Liquid, including whitespace control" do
    html = "before \n {%- if visible -%} shown {%- else -%} hidden {%- endif -%} after"

    assert Villain.parse_and_render(html, Context.new(%{"visible" => true})) == "beforeshownafter"
    assert Villain.parse_and_render(html, Context.new(%{"visible" => false})) == "beforehiddenafter"
  end

  test "retains parse error handling when Liquid is malformed" do
    assert ExUnit.CaptureLog.capture_log(fn ->
             assert Villain.parse_and_render("{% if visible %}unclosed", Context.new(%{})) ==
                      "!!! Error parsing liquex template !!!"
           end) =~ "Error parsing liquex template"
  end
end
