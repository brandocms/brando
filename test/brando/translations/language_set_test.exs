defmodule Brando.Translations.LanguageSetTest do
  # The language versions of an entry are one set, the same from every
  # member: everything reached through alternate links and group membership,
  # followed through other versions (#3942). Articles in three languages
  # (test/support/three_language_articles.exs). Not async: the site's
  # languages are the application's.
  use Brando.ConnCase, async: false

  import Brando.Test.Users
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.ThreeLanguageTest.Article
  alias Brando.ThreeLanguageTest.IndependentArticle
  alias Brando.Translations

  setup do
    put_test_env(:languages, [
      [value: "no", text: "Norsk"],
      [value: "en", text: "English"],
      [value: "de", text: "Deutsch"]
    ])

    %{user: Factory.insert(:random_user)}
  end

  # Inserted as it is: with group authorization, the read policy's creator
  # is set by `owned_by/2`
  defp article(user, language) do
    Repo.insert!(%Article{
      title: "Tittel #{language}",
      slug: "tittel-#{language}",
      language: String.to_existing_atom(language),
      status: :published,
      creator_id: user.id
    })
  end

  defp independent(article), do: Repo.get!(IndependentArticle, article.id)

  defp link(a, b), do: :ok = Article.Alternate.add(a.id, b.id)

  defp trash(entry),
    do: Repo.update_all(from(e in Article, where: e.id == ^entry.id), set: [deleted_at: DateTime.utc_now(:second)])

  defp put_groups do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    {:ok, _} = Brando.Authorization.Migration.run()
    :ok
  end

  # The read policy lets a person read the entries they created
  defp owned_by(entry, user),
    do: Repo.update_all(from(e in Article, where: e.id == ^entry.id), set: [creator_id: user.id])

  defp ids(versions), do: Map.new(versions, fn {language, version} -> {language, version.id} end)

  describe "a synchronized type" do
    setup %{user: user} do
      source = article(user, "no")
      {:ok, english} = Translations.create_target(Article, source.id, :en, user)
      german = article(user, "de")
      link(source, german)
      %{source: source, english: english, german: german}
    end

    test "a translation has the version linked to its source", c do
      assert ids(Translations.versions_by_language(Article, c.english, nil)) == %{
               "no" => c.source.id,
               "de" => c.german.id
             }

      assert Translations.missing_languages(Article, c.english) == []

      # The same set from every member
      assert ids(Translations.versions_by_language(Article, c.german, nil)) == %{
               "no" => c.source.id,
               "en" => c.english.id
             }
    end

    test "the version is reached through the source, and is not the translation's own link", c do
      %{linked: linked} = Translations.language_versions(Article, c.english, nil)

      assert [
               %{entry: %{id: german_id}, linked?: false, via: "no"},
               %{entry: %{id: source_id}, linked?: true, via: nil}
             ] = linked

      assert {german_id, source_id} == {c.german.id, c.source.id}
    end

    test "a version is not created from an entry linked to one with a version in that language", c do
      newcomer = article(c.user, "en")
      link(newcomer, c.source)

      assert {:error, :language_exists} = Translations.create_target(Article, newcomer.id, :de, c.user)
      refute Translations.get_member(Article, newcomer.id)
    end
  end

  test "a translation's sibling in its group comes before another version linked to their source", %{user: user} do
    source = article(user, "no")
    {:ok, english} = Translations.create_target(Article, source.id, :en, user)
    # Older than the group's German translation, and linked after it was made
    independent = article(user, "de")
    {:ok, german} = Translations.create_target(Article, source.id, :de, user)
    link(source, independent)
    assert independent.id < german.id

    assert %{"de" => %{id: id}} = Translations.versions_by_language(Article, english, nil)
    assert id == german.id
  end

  test "a trashed member is not replaced while the set holds a version in its language outside the trash", %{
    user: user
  } do
    source = article(user, "no")
    {:ok, english} = Translations.create_target(Article, source.id, :en, user)
    {:ok, german} = Translations.create_target(Article, source.id, :de, user)
    trash(german)
    other_german = article(user, "de")
    link(english, other_german)

    assert {:error, :language_exists} = Translations.replace_trashed_target(Article, source.id, :de, user)
    assert %{deleted_at: %DateTime{}} = Repo.get!(Article, german.id)
    assert Translations.get_member(Article, german.id)
  end

  describe "a type that is not synchronized" do
    test "an entry has the versions linked to the one it is linked to", %{user: user} do
      norsk = article(user, "no")
      english = article(user, "en")
      german = article(user, "de")
      link(norsk, english)
      link(norsk, german)

      english = independent(english)

      assert ids(Translations.versions_by_language(IndependentArticle, english, nil)) == %{
               "no" => norsk.id,
               "de" => german.id
             }

      alone = article(user, "en") |> independent()

      assert Translations.copy_languages(IndependentArticle, [english, independent(german), alone]) == %{
               english.id => [],
               german.id => [],
               alone.id => Translations.missing_languages(IndependentArticle, alone)
             }

      assert Enum.sort(Translations.missing_languages(IndependentArticle, alone)) == ["de", "no"]
      assert Translations.missing_languages(IndependentArticle, english) == []
    end
  end

  describe "a person who may not read every version" do
    setup %{user: user} do
      source = article(user, "no")
      {:ok, english} = Translations.create_target(Article, source.id, :en, user)
      put_groups()
      editor = Brando.ThreeLanguageTest.grant_read(insert_user(permissions: ~w(brando.admin.access)))
      owned_by(english, editor)
      %{editor: editor, source: source, english: english}
    end

    test "is offered a version reached through one they may not read, and sees nothing of that one", c do
      german = article(c.user, "de")
      link(c.source, german)
      owned_by(german, c.editor)

      set = Translations.language_versions(Article, c.english, c.editor)
      assert ids(Translations.versions_by_language(Article, c.english, c.editor)) == %{"de" => german.id}
      # The Norwegian source is not in it but for its language
      assert [%{entry: %{id: german_id}, via: "no"}] = set.linked
      assert german_id == german.id
      # Norwegian has a version, which they may not read
      assert "no" in set.taken
    end

    test "is offered the German version they may read, not one they may not", c do
      unreadable = article(c.user, "de")
      link(c.english, unreadable)
      readable = article(c.user, "de")
      link(c.source, readable)
      owned_by(readable, c.editor)

      assert ids(Translations.versions_by_language(Article, c.english, c.editor)) == %{"de" => readable.id}
    end
  end
end
