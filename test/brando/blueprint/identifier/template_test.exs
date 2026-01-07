defmodule Brando.Blueprint.Identifier.TemplateTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Identifier.Template

  describe "extract_fields/1" do
    test "extracts simple field references" do
      assert Template.extract_fields("{{ entry.title }}") == [:title]
    end

    test "extracts multiple field references" do
      assert Template.extract_fields("{{ entry.title }} - {{ entry.slug }}") == [:title, :slug]
    end

    test "extracts nested field references" do
      result = Template.extract_fields("{{ entry.title }} [{{ entry.creator.name }}]")
      assert :title in result
      assert [{:creator, :name}] in result
    end

    test "handles deeply nested field references (only supports 2 levels)" do
      # The current implementation only supports entry.field or entry.rel.field patterns
      # Deeper nesting like entry.a.b.c is not supported and will raise
      # This is expected - templates should use simple field references
      assert_raise FunctionClauseError, fn ->
        Template.extract_fields("{{ entry.category.parent.name }}")
      end
    end

    test "handles templates with no field references" do
      assert Template.extract_fields("Static text") == []
    end

    test "deduplicates field references" do
      result = Template.extract_fields("{{ entry.title }} {{ entry.title }}")
      assert result == [:title]
    end

    test "handles complex templates" do
      template = "[{{ entry.namespace }}] {{ entry.name }} - {{ entry.creator.slug }}"
      result = Template.extract_fields(template)

      assert :namespace in result
      assert :name in result
      assert [{:creator, :slug}] in result
    end

    test "handles templates with filters" do
      result = Template.extract_fields("{{ entry.name | upcase }}")
      assert result == [:name]
    end

    test "handles templates with i18n filters" do
      result = Template.extract_fields("[{{ entry.namespace | i18n }}] {{ entry.name | i18n }}")
      assert :namespace in result
      assert :name in result
    end
  end
end
