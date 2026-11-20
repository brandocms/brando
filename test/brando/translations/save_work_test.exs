defmodule Brando.Translations.SaveWorkTest do
  # Answered translation work saved as the translation form saves it
  # (Brando.Translations.save_work/5), and opened again (reopen_work/3).
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    {:ok, source} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "tittel-#{System.unique_integer([:positive])}", language: "no", status: "published"},
        user
      )

    first = TranslationFixtures.add_block(source, module, user, "<p>Første avsnitt</p>", 0)
    second = TranslationFixtures.add_block(source, module, user, "<p>Andre avsnitt</p>", 1)
    {:ok, target} = Translations.create_target(Article, source.id, :en, user)

    %{user: user, source: source, target: target, first: first, second: second}
  end

  defp body(block), do: "entry_blocks/#{block.uid}/refs/body/text"

  defp open_items(id) do
    Article
    |> Translations.get_pending_version(id)
    |> Map.fetch!(:work_items)
    |> Enum.filter(&is_nil(&1.resolved_at))
    |> Enum.map(&{&1.kind, &1.path})
    |> Enum.sort()
  end

  defp texts(id) do
    {:ok, entry} = Translations.load_entry(Article, id)
    bodies = Enum.map(entry.entry_blocks, fn join -> hd(join.block.refs).data.data.text end)
    {entry.title, bodies}
  end

  test "saves the texts at their keys, resolves what it answered and leaves the rest open", c do
    before_uids = Enum.map(elem(Translations.load_entry(Article, c.target.id), 1).entry_blocks, & &1.block.uid)

    assert {:ok, result} =
             Translations.save_work(
               Article,
               c.target.id,
               %{texts: %{"title" => "Title", body(c.first) => "<p>First paragraph</p>"}, acknowledged: []},
               c.user
             )

    assert texts(c.target.id) == {"Title", ["<p>First paragraph</p>", "<p>Andre avsnitt</p>"]}
    assert open_items(c.target.id) == [{:translate, body(c.second)}]

    assert result.resolved |> Enum.map(&{&1.kind, &1.path}) |> Enum.sort() ==
             [{:translate, body(c.first)}, {:translate, "title"}]

    assert result.open == 1
    # The structure is the translation's own blocks, as they were
    {:ok, saved} = Translations.load_entry(Article, c.target.id)
    assert Enum.map(saved.entry_blocks, & &1.block.uid) == before_uids
    # An unpublished translation stays unpublished
    assert saved.status == :draft
  end

  test "an acknowledged text, and a text equal to the one it has, are resolved without a change", c do
    assert {:ok, _} =
             Translations.save_work(
               Article,
               c.target.id,
               %{texts: %{"title" => "Tittel"}, acknowledged: [body(c.first)]},
               c.user
             )

    assert texts(c.target.id) == {"Tittel", ["<p>Første avsnitt</p>", "<p>Andre avsnitt</p>"]}
    assert open_items(c.target.id) == [{:translate, body(c.second)}]
  end

  test "a published translation is saved published", c do
    {:ok, _} = SyncTest.update_article(c.target.id, %{status: "published"}, c.user)

    assert {:ok, %{entry: %{status: :published}}} =
             Translations.save_work(Article, c.target.id, %{texts: %{"title" => "Title"}}, c.user)

    assert Repo.get!(Article, c.target.id).title == "Title"
  end

  test "a source or an entry outside a group is not a translation", c do
    assert {:error, :not_translation} = Translations.save_work(Article, c.source.id, %{texts: %{}}, c.user)

    {:ok, lone} =
      SyncTest.create_article(%{title: "Alone", slug: "alone-#{c.source.id}", language: "no", status: "draft"}, c.user)

    assert {:error, :not_translation} = Translations.save_work(Article, lone.id, %{texts: %{}}, c.user)
  end

  test "reopen_work opens the resolved items again once the texts are back", c do
    before = open_items(c.target.id)

    {:ok, revision} =
      Brando.Revisions.create_revision(
        Repo.get!(Article, c.target.id) |> Repo.preload(Brando.Blueprint.preloads_for(Article)),
        c.user
      )

    {:ok, result} =
      Translations.save_work(
        Article,
        c.target.id,
        %{texts: %{"title" => "Title"}, acknowledged: [body(c.first)]},
        c.user
      )

    {:ok, _} = Brando.Revisions.set_entry_to_revision(Article, c.target.id, revision.revision, c.user)
    assert {:ok, 3} = Translations.reopen_work(Article, c.target.id, result.resolved)
    assert open_items(c.target.id) == before
    assert texts(c.target.id) == {"Tittel", ["<p>Første avsnitt</p>", "<p>Andre avsnitt</p>"]}
  end
end
