defmodule Brando.SEO.GenerateTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.SEO.Generate

  describe "prompt_for/4" do
    test "uses the blueprint's own prompt and appends the entry context" do
      entry = %Pages.Page{
        title: "Om oss",
        language: "no",
        rendered_blocks: "<p>Vi lager nettsteder</p>"
      }

      {:ok, prompt, ai_opts} = Generate.prompt_for(Pages.Page, entry, :meta_description)

      assert prompt =~ "Write an SEO meta description"
      assert prompt =~ "Context:\ntitle: Om oss\nblocks: Vi lager nettsteder\nlanguage: no"
      assert Keyword.get(ai_opts, :context) == [:title, :blocks, :language]
    end

    test "a picked set of context fields replaces the blueprint's" do
      entry = %Pages.Page{title: "Om oss", language: "no", rendered_blocks: "<p>Vi lager nettsteder</p>"}

      {:ok, prompt, _ai_opts} =
        Generate.prompt_for(Pages.Page, entry, :meta_description, context_fields: [:title])

      assert prompt =~ "Context:\ntitle: Om oss"
      refute prompt =~ "Vi lager nettsteder"
    end

    test "reads the site's stored pick when the caller passes none" do
      user = Factory.insert(:random_user)
      {:ok, _seo} = Generate.store_context_fields(Pages.Page, "en", [:title], user)
      entry = %Pages.Page{title: "Stored pick", language: "en", rendered_blocks: "<p>Left out</p>"}

      {:ok, prompt, _ai_opts} = Generate.prompt_for(Pages.Page, entry, :meta_description)

      assert prompt =~ "Context:\ntitle: Stored pick"
      refute prompt =~ "Left out"
    end

    test "refuses an entry with nothing to describe" do
      entry = %Pages.Page{title: nil, language: "en"}

      assert Generate.prompt_for(Pages.Page, entry, :meta_description, context_fields: [:title]) ==
               {:error, :no_context}
    end
  end

  describe "default_prompt/2" do
    test "names the entry's language and the length the field is shown at" do
      description = Generate.default_prompt(%Pages.Page{language: "no"}, :meta_description)
      title = Generate.default_prompt(%Pages.Page{language: "no"}, :meta_title)

      assert description =~ "meta description"
      assert description =~ "155 characters"
      assert description =~ Brando.AI.language_name("no")

      assert title =~ "meta title"
      assert title =~ "60 characters"
    end
  end

  describe "context_fields/2" do
    test "prefers what the blueprint declares over the schema's own fields" do
      assert Generate.context_fields(Pages.Page, context: [:title, :blocks]) == [:title, :blocks]
      assert :title in Generate.context_fields(Pages.Page)
      assert :blocks in Generate.context_fields(Pages.Page)
    end
  end

  describe "generate/5" do
    test "refuses a field it will not write" do
      assert Generate.generate(Pages.Page, 1, :title) == {:error, :unsupported_field}
    end

    test "reports an entry that is not there" do
      assert Generate.generate(Pages.Page, 0, :meta_description) == {:error, {:page, :not_found}}
    end
  end

  describe "context field storage" do
    test "stores a pick per schema and language, and forgets an empty one" do
      user = Factory.insert(:random_user)

      assert Generate.stored_context_fields(Pages.Page, "en") == nil

      {:ok, _seo} = Generate.store_context_fields(Pages.Page, "en", [:title, "blocks"], user)
      assert Generate.stored_context_fields(Pages.Page, "en") == [:title, :blocks]
      assert Generate.context_field_map([Pages.Page], "en") == %{Pages.Page => [:title, :blocks]}

      {:ok, _seo} = Generate.store_context_fields(Pages.Page, "en", [], user)
      assert Generate.stored_context_fields(Pages.Page, "en") == nil
    end

    test "a schema with no stored pick falls back to the blueprint" do
      map = Generate.context_field_map([Pages.Page], "en")

      assert map[Pages.Page] == Generate.context_fields(Pages.Page)
    end
  end
end
