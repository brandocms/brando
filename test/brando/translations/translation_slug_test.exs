defmodule Brando.Translations.TranslationSlugTest do
  # The slug a new translation gets (#3869): the source's own when the slug is
  # unique per language, the source's with the language appended when it is
  # unique across the table.
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.SlugScopeTest
  alias Brando.SlugScopeTest.LanguageArticle
  alias Brando.SlugScopeTest.StatusArticle
  alias Brando.SlugScopeTest.TableArticle
  alias Brando.Translations

  setup do
    %{user: Factory.insert(:random_user)}
  end

  defp article(schema, slug, language, user, status \\ "published") do
    create = :"create_#{schema.__naming__().singular}"

    {:ok, entry} =
      apply(SlugScopeTest, create, [%{title: "Banzha", slug: slug, language: language, status: status}, user])

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

  # The copy is a draft: its slug is looked up among the language's drafts,
  # not among the published entries the source is one of.
  test "a slug unique per language and status is free among the language's drafts", %{user: user} do
    source = article(StatusArticle, "banzha", "no", user)
    _draft = article(StatusArticle, "banzha", "en", user, "draft")

    assert {:ok, %{slug: "banzha-2", language: :en, status: :draft}} =
             Translations.create_target(StatusArticle, source.id, :en, user)
  end
end
