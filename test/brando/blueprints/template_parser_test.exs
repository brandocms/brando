defmodule Brando.Blueprint.TemplateParserTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.TemplateParser

  test "standard Blueprint templates use the base Liquex parser" do
    template = "{{ entry.title }} [{{ entry.category.name }}]"

    assert TemplateParser.parser_for(template) == Liquex.Parser.Base
    assert {:ok, _parsed} = TemplateParser.parse(template)
  end

  test "templates containing Brando tags retain the full parser" do
    template = "{% route preview_url show { entry.preview_key } %}"

    assert TemplateParser.parser_for(template) == Brando.Villain.LiquexParser
    assert {:ok, _parsed} = TemplateParser.parse(template)
  end

  test "whitespace-control tags are detected" do
    assert TemplateParser.parser_for("{%- ref refs.title %}") == Brando.Villain.LiquexParser
  end

  test "all Brando tag grammars remain available through the full parser" do
    templates = [
      "{% headless_ref refs.table %}",
      "{% inspect entry.cover %}",
      "{% ref refs.title %}",
      "{% link variable_link %}",
      "{% picture entry.cover { sizes: 'auto' } %}",
      "{% video entry.video { autoplay: true } %}",
      "{% route page_path show { entry.uri } %}",
      "{% route_i18n entry.language page_path show { entry.uri } %}",
      "{% fragment parent key en %}",
      "{% hide %}{% endhide %}",
      "{% t no 'Norsk' %}",
      "{% datasource %}{% enddatasource %}"
    ]

    for template <- templates do
      assert TemplateParser.parser_for(template) == Brando.Villain.LiquexParser
      assert {:ok, _parsed} = TemplateParser.parse(template)
    end
  end
end
