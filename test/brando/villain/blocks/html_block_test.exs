defmodule Brando.Villain.Blocks.HtmlBlockTest do
  # An HTML ref's template with its typed parameters filled in. The
  # payloads that try to break out of an attribute, an element or a script
  # are in test/fixtures/html_ref/values.json.
  use ExUnit.Case, async: true

  alias Brando.Villain.Blocks.HtmlBlock
  alias Brando.Villain.Blocks.HtmlBlock.Data
  alias Brando.Villain.Blocks.HtmlBlock.Param

  @payloads "test/fixtures/html_ref/values.json" |> File.read!() |> Jason.decode!()

  defp render(text, type, value) do
    HtmlBlock.render(%Data{text: text, params: [%Param{key: "v", label: "V", type: type}], values: %{"v" => value}})
  end

  defp payload(name), do: Map.fetch!(@payloads, name)

  test "a template without parameters renders as it is" do
    text = ~s(<div class="x">{{ entry.title }} {{ v }}</div>)
    assert HtmlBlock.render(%Data{text: text, params: [], values: %{"v" => "x"}}) == text
  end

  test "an undeclared placeholder is left for the page's Liquid pass" do
    assert render("{{ v }}|{{ other }}|{{ entry.title }}", :text, "a") == "a|{{ other }}|{{ entry.title }}"
  end

  test "a placeholder may have spaces or none" do
    assert render("{{v}}-{{  v  }}", :id, "a1") == "a1-a1"
  end

  describe "id" do
    test "takes letters, digits, _ and -" do
      assert render(~s[<script>init("{{ v }}")</script>], :id, "Abc_9-x") == ~s[<script>init("Abc_9-x")</script>]
    end

    test "renders nothing for anything else, in a script or an attribute" do
      for name <- ~w(script_string_breakout script_close attribute_breakout) do
        assert render(~s[<script>init("{{ v }}")</script>], :id, payload(name)) == ~s[<script>init("")</script>]
      end
    end
  end

  describe "number" do
    test "takes an integer or a decimal" do
      assert render("<script>n = {{ v }};</script>", :number, "-12.5") == "<script>n = -12.5;</script>"
      assert render("{{ v }}", :number, 42) == "42"
    end

    test "renders nothing for anything else" do
      assert render("<script>n = {{ v }};</script>", :number, payload("number_with_code")) == "<script>n = ;</script>"
      assert render("{{ v }}", :number, "1e5") == ""
    end
  end

  describe "url" do
    test "takes https and relative addresses, escaped for an attribute" do
      assert render(~s(<a href="{{ v }}">), :url, payload("relative_url")) == ~s(<a href="/checkin?id=42">)

      assert render(~s(<a href="{{ v }}">), :url, payload("https_url_with_quote")) ==
               ~s(<a href="https://example.com/?a=1&amp;b=&quot;x">)
    end

    test "renders nothing for another scheme" do
      for name <- ~w(javascript_url entity_javascript_url data_url http_url) do
        assert render(~s(<a href="{{ v }}">), :url, payload(name)) == ~s(<a href="">)
      end
    end
  end

  describe "text" do
    test "is escaped for element content and quoted attributes" do
      rendered = render(~s(<div title="{{ v }}">{{ v }}</div>), :text, payload("attribute_breakout"))
      refute rendered =~ ~s(" onmouseover)
      assert rendered =~ ~s(title="&quot; onmouseover=&quot;)

      rendered = render("<div>{{ v }}</div>", :text, payload("element_breakout"))
      refute rendered =~ "<script"
      assert rendered =~ "&lt;/div&gt;&lt;script&gt;"
    end

    test "never forms Liquid with the template's own braces" do
      for type <- [:text, :url] do
        rendered = render("<pre>{{{ v }}}</pre>", type, "% inspect entry %")
        refute rendered =~ "{%"

        context = Liquex.Context.new(%{"entry" => %{"title" => "SECRET"}})
        refute Brando.Villain.parse_and_render(rendered, context) =~ "SECRET"
      end
    end

    test "never forms Liquid for the page's Liquid pass" do
      rendered = render("<p>{{ v }}</p>", :text, payload("liquid"))
      refute rendered =~ "{{"
      refute rendered =~ "{%"

      context = Liquex.Context.new(%{"entry" => %{"title" => "SECRET"}})
      output = Brando.Villain.parse_and_render(rendered, context)
      refute output =~ "SECRET"
      assert output =~ "&#123;&#123; entry.title &#125;&#125;"
    end
  end

  test "a missing or invalid value renders as nothing" do
    assert render("[{{ v }}]", :text, nil) == "[]"
    assert render("[{{ v }}]", :id, "") == "[]"
    assert HtmlBlock.render(%Data{text: "[{{ v }}]", params: [%Param{key: "v", type: :id}], values: %{}}) == "[]"
  end

  test "the parser's html/2 renders the template" do
    data = %Data{text: "<i>{{ v }}</i>", params: [%Param{key: "v", type: :text}], values: %{"v" => "<b>"}}
    assert Brando.Villain.Parser.html(data, %{}) == "<i>&lt;b&gt;</i>"
  end

  describe "changeset" do
    test "refuses a value invalid for its type" do
      changeset =
        Data.changeset(%Data{}, %{
          "text" => "{{ v }}",
          "params" => [%{"key" => "v", "label" => "V", "type" => "id"}],
          "values" => %{"v" => payload("attribute_breakout")}
        })

      refute changeset.valid?
      assert {_, [keys: "v"]} = changeset.errors[:values]
    end

    test "refuses a malformed or repeated key" do
      refute Data.changeset(%Data{}, %{"params" => [%{"key" => "Bad Key", "type" => "text"}]}).valid?

      refute Data.changeset(%Data{}, %{"params" => [%{"key" => "a", "type" => "text"}, %{"key" => "a", "type" => "id"}]}).valid?
    end
  end
end
