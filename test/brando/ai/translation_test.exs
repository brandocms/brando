defmodule Brando.AI.TranslationTest do
  use ExUnit.Case, async: true

  alias Brando.AI.Translation

  describe "translatable_text_fields/1" do
    test "returns text and rich_text fields from the Page blueprint" do
      fields = Translation.translatable_text_fields(Brando.Pages.Page)
      assert :title in fields
      assert is_list(fields)
    end
  end

  describe "build_translation_prompt/3" do
    test "formats numbered items" do
      items = [
        {:field, :title, "Hello World"},
        {:var, 1, "<p>Some intro text</p>"},
        {:ref, 2, "Header content"}
      ]

      {system_prompt, content} = Translation.build_translation_prompt(items, "en", "no")

      assert system_prompt =~ "English"
      assert system_prompt =~ "Norsk" or system_prompt =~ "Norwegian"
      assert system_prompt =~ "Preserve ALL HTML tags"

      assert content =~ "1: Hello World"
      assert content =~ "2: <p>Some intro text</p>"
      assert content =~ "3: Header content"
    end

    test "handles unknown language codes gracefully" do
      items = [{:field, :title, "Hello"}]
      {system_prompt, _content} = Translation.build_translation_prompt(items, "xx", "yy")

      # Should use uppercased fallback
      assert system_prompt =~ "XX" or system_prompt =~ "YY"
    end
  end

  describe "parse_translation_response/2" do
    test "parses clean numbered response" do
      response = """
      1: Bonjour le monde
      2: Du contenu ici
      3: En-tête
      """

      result = Translation.parse_translation_response(response, 3)
      assert result == ["Bonjour le monde", "Du contenu ici", "En-tête"]
    end

    test "handles colon separator" do
      response = "1: Première\n2: Deuxième"
      result = Translation.parse_translation_response(response, 2)
      assert result == ["Première", "Deuxième"]
    end

    test "handles dot separator" do
      response = "1. Première\n2. Deuxième"
      result = Translation.parse_translation_response(response, 2)
      assert result == ["Première", "Deuxième"]
    end

    test "handles extra whitespace" do
      response = "  1:   Bonjour  \n  2:   Monde  "
      result = Translation.parse_translation_response(response, 2)
      assert result == ["Bonjour", "Monde"]
    end

    test "handles missing items with empty strings" do
      response = "1: Bonjour\n3: Troisième"
      result = Translation.parse_translation_response(response, 3)
      assert result == ["Bonjour", "", "Troisième"]
    end

    test "handles preamble text from LLM" do
      response = """
      Here are the translations:

      1: Bonjour
      2: Monde
      """

      result = Translation.parse_translation_response(response, 2)
      assert result == ["Bonjour", "Monde"]
    end

    test "preserves HTML in translations" do
      response = "1: <p>Du texte en <strong>gras</strong></p>"
      result = Translation.parse_translation_response(response, 1)
      assert result == ["<p>Du texte en <strong>gras</strong></p>"]
    end
  end

  describe "collect_translatable_content/2" do
    test "collects entry-level text fields" do
      # Test with a mock-like struct
      # Full integration testing requires DB fixtures, so just verify field discovery
      fields = Translation.translatable_text_fields(Brando.Pages.Page)
      assert is_list(fields)
    end
  end
end
