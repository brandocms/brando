defmodule Brando.Translations.TranslationSlugTest do
  # The slug a new translation gets (#3869): the source's own when the slug is
  # unique per language, the source's with the language appended when it is
  # unique across the table.
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.SlugScopeTest
  alias Brando.SlugScopeTest.LanguageArticle
  alias Brando.SlugScopeTest.TableArticle
  alias Brando.Translations

  setup do
    %{user: Factory.insert(:random_user)}
  end

  defp article(schema, slug, language, user) do
    create = if schema == LanguageArticle, do: :create_language_article, else: :create_table_article

    {:ok, entry} =
      apply(SlugScopeTest, create, [%{title: "Banzha", slug: slug, language: language, status: "published"}, user])

    entry
  end

  test "a slug unique per language is kept", %{user: user} do
    source = article(LanguageArticle, "banzha", "no", user)

    assert {:ok, %{slug: "banzha", language: :en}} = Translations.create_target(LanguageArticle, source.id, :en, user)
  end

  test "a slug unique across the table gets the language appended", %{user: user} do
    source = article(TableArticle, "banzha", "no", user)

    assert {:ok, %{slug: "banzha-en", language: :en}} = Translations.create_target(TableArticle, source.id, :en, user)
  end

  test "a slug the language already uses is numbered", %{user: user} do
    source = article(LanguageArticle, "banzha", "no", user)
    _taken = article(LanguageArticle, "banzha", "en", user)

    assert {:ok, %{slug: slug, language: :en}} = Translations.create_target(LanguageArticle, source.id, :en, user)
    assert slug == "banzha-2"
  end
end
