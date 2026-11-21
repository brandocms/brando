defmodule E2eProject.RichTextRowsTest do
  # A rich text in a subform's rows, drawn as the site draws it (the
  # article's quotes), is held to the same check as a top-level one on the
  # paths that write it: the entry's changeset, which the admin form's save
  # and a translate proposal's apply both go through.
  use E2eProject.DataCase, async: false

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Translate
  alias Brando.Translations
  alias Brando.Translations.Work
  alias E2eProject.SyncTest
  alias E2eProject.SyncTest.Article

  @unsafe ~s{<p><a href="javascript:alert(1)">Quote</a></p>}

  setup do
    suffix = String.slice(Ecto.UUID.generate(), 0, 8)

    user =
      Repo.insert!(%Brando.Users.User{
        name: "Rich text rows",
        email: "rich-text-rows-#{suffix}@brandocms.com",
        role: :superuser,
        password: "brandocms",
        language: :en
      })

    %{user: user, suffix: suffix}
  end

  test "an article's quote with unsafe markup is refused on its row", %{
    user: user,
    suffix: suffix
  } do
    params = %{
      title: "Article",
      slug: "article-#{suffix}",
      language: "en",
      status: "draft",
      quotes: [%{text: @unsafe}]
    }

    changeset = Article.changeset(%Article{}, params, user)
    refute changeset.valid?
    assert [%{errors: [text: _]}] = Ecto.Changeset.get_change(changeset, :quotes)

    assert {:ok, %{quotes: [%{text: "<p>Quote</p>"}]}} =
             SyncTest.create_article(
               %{params | quotes: [%{text: "<p>Quote</p><!-- x -->"}]},
               user
             )
  end

  test "a translate operation whose quote text holds a javascript: link is refused",
       %{user: user, suffix: suffix} do
    {:ok, source} =
      SyncTest.create_article(
        %{
          title: "Tittel",
          slug: "tittel-#{suffix}",
          language: "no",
          status: "published",
          quotes: [%{text: "Sitatet"}]
        },
        user
      )

    {:ok, target} = Translations.create_target(Article, source.id, :en, user)
    {:ok, %{units: units}} = Work.translation_units(Article, target.id)
    units = Enum.filter(units, & &1.answerable)
    key = Enum.find_value(units, &(String.starts_with?(&1.key, "quotes/") && &1.key))
    assert key

    texts = Map.new(units, &{&1.key, "Text"}) |> Map.put(key, @unsafe)

    op = %Translate{
      target: {Article, target.id},
      source_digest:
        Work.token(%{type: to_string(Article), id: target.id, language: "en"}, units),
      texts: texts
    }

    # Refused when prepared, naming the row's text
    assert {:ok, proposal} = Proposals.propose([op], user)
    assert [%{code: :unsafe_text, key: ^key}] = proposal.problems

    # and by the save an apply makes, the entry's changeset
    assert {:ok, changeset, _version_id} =
             Translations.work_changeset(Article, target.id, texts, user)

    refute changeset.valid?
    assert [%{errors: [text: _]}] = Ecto.Changeset.get_change(changeset, :quotes)

    {:ok, saved} = Translations.load_entry(Article, target.id)
    refute Enum.any?(saved.quotes, &(&1.text =~ "javascript"))
  end
end
