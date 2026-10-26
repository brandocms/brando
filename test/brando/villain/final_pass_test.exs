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

  test "inert_liquid/1 leaves Liquid as text, and script and style as they are" do
    html =
      ~s(<p title="{{ title }}">{{ title }} {% if true %}x{% endif %}</p>) <>
        ~s(<script type="application/ld+json">{"a": {"b": 1}}</script><style>p { color: red }</style>)

    inert = Villain.inert_liquid(html)

    assert inert ==
             ~s(<p title="&#123;&#123; title &#125;&#125;">&#123;&#123; title &#125;&#125; ) <>
               ~s(&#123;% if true %&#125;x&#123;% endif %&#125;</p>) <>
               ~s(<script type="application/ld+json">{"a": {"b": 1}}</script><style>p { color: red }</style>)

    assert Floki.text(Floki.parse_fragment!(inert)) == Floki.text(Floki.parse_fragment!(html))
    # A custom element named like one is not raw text
    assert Villain.inert_liquid("<script-x>{</script-x></script>}") == "<script-x>&#123;</script-x></script>&#125;"

    assert Villain.parse_and_render(Villain.inert_liquid("<p>{{ title }}</p>"), Context.new(%{"title" => "T"})) ==
             "<p>&#123;&#123; title &#125;&#125;</p>"
  end
end
