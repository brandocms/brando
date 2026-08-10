defmodule Brando.Blueprint.TemplateParserTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.TemplateParser
  alias Brando.Exception.BlueprintError

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

  test "tag arguments may span multiple lines" do
    templates = [
      """
      {% picture entry.cover {
           sizes: 'auto',
           lazyload: true
      } %}
      """,
      """
      {% video entry.video {
           autoplay: true,
           muted: true
      } %}
      """,
      """
      {% route page_path show {
           entry.uri
      } %}
      """
    ]

    for template <- templates do
      assert {:ok, _parsed} = TemplateParser.parse(template)
    end
  end

  test "parse!/2 reports the Blueprint setting and parser location" do
    template = "{{ entry.title "

    error =
      assert_raise BlueprintError, fn ->
        TemplateParser.parse!(template, :identifier)
      end

    assert Exception.message(error) ==
             "Invalid Blueprint identifier template at line 1: unclosed `{{` (expected `}}`)\n\n#{template}"
  end

  test "identifier and absolute URL macros preserve contextual parse errors" do
    identifier_module = unique_module("InvalidIdentifier")
    absolute_url_module = unique_module("InvalidAbsoluteURL")

    identifier_error =
      assert_raise BlueprintError, fn ->
        compile_macro(identifier_module, Brando.Blueprint.Identifier.DSL, :identifier, "{{ entry.title ")
      end

    absolute_url_error =
      assert_raise BlueprintError, fn ->
        compile_macro(absolute_url_module, Brando.Blueprint.AbsoluteURL, :absolute_url, "{{ entry.slug ")
      end

    assert Exception.message(identifier_error) =~ "Invalid Blueprint identifier template at line 1"
    assert Exception.message(absolute_url_error) =~ "Invalid Blueprint absolute URL template at line 1"
  end

  defp compile_macro(module, imported_module, macro, value) do
    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          import unquote(imported_module)
          unquote(macro)(unquote(value))
        end
      end
    )
  end

  defp unique_module(suffix) do
    Module.concat(__MODULE__, "#{suffix}#{System.unique_integer([:positive])}")
  end
end
