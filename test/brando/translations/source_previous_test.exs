defmodule Brando.Translations.SourcePreviousTest do
  # A review item keeps the source's text the translation was last synced
  # against (`source_previous`), from the texts its member keeps beside the
  # baseline's digests (`baseline_texts`).
  use Brando.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations
  alias Brando.Translations.Member

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

    block = TranslationFixtures.add_block(source, module, user, "<p>Første avsnitt</p>", 0)
    {:ok, target} = Translations.create_target(Article, source.id, :en, user, mark_translate: false)

    %{user: user, source: source, target: target, block: block}
  end

  defp body(block), do: "entry_blocks/#{block.uid}/refs/body/text"

  defp member(entry) do
    member = Translations.get_member(Article, entry.id)
    %{member | baseline_texts: Repo.one(from m in Member, where: m.id == ^member.id, select: m.baseline_texts)}
  end

  defp queries(fun) do
    parent = self()
    handler = "source-previous-#{inspect(make_ref())}"

    :telemetry.attach(
      handler,
      Brando.repo().config()[:telemetry_prefix] ++ [:query],
      fn _, _, meta, _ -> if self() == parent, do: send(parent, {handler, meta.query}) end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect(handler, [])
  end

  defp collect(handler, acc) do
    receive do
      {^handler, query} -> collect(handler, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp retitle(c, title), do: {:ok, _} = SyncTest.update_article(c.source.id, %{title: title}, c.user)

  defp open_review(c, path) do
    case Translations.get_pending_version(Article, c.target.id) do
      nil -> []
      version -> version.work_items
    end
    |> Enum.find(&(&1.kind == :review and &1.path == path and is_nil(&1.resolved_at)))
  end

  test "a new translation's member keeps the source's texts beside their digests", c do
    texts = member(c.target).baseline_texts

    assert texts == %{"title" => "Tittel", body(c.block) => "<p>Første avsnitt</p>"}
    assert Map.keys(texts) -- Map.keys(member(c.target).baseline) == []
  end

  test "a review item raised by a source change carries the text before the change", c do
    retitle(c, "Ny tittel")

    assert %{source_previous: "Tittel"} = open_review(c, "title")
    assert member(c.target).baseline_texts["title"] == "Ny tittel"
  end

  test "a second change before the review is done keeps the first previous text", c do
    retitle(c, "Ny tittel")
    retitle(c, "Nyere tittel")

    assert %{source_previous: "Tittel"} = open_review(c, "title")
    assert member(c.target).baseline_texts["title"] == "Nyere tittel"
  end

  test "the next review after a resolved one carries the text of the sync in between", c do
    retitle(c, "Ny tittel")
    {:ok, _} = Translations.save_work(Article, c.target.id, %{texts: %{"title" => "New title"}}, c.user)
    assert open_review(c, "title") == nil

    retitle(c, "Tredje tittel")

    assert %{source_previous: "Ny tittel"} = open_review(c, "title")
  end

  test "a member synced before the texts were kept raises review without them, and gains them", c do
    from(m in Member, where: m.entry_id == ^c.target.id and m.entry_type == ^to_string(Article))
    |> Repo.update_all(set: [baseline_texts: %{}])

    retitle(c, "Ny tittel")

    assert %{source_previous: nil} = open_review(c, "title")
    assert member(c.target).baseline_texts["title"] == "Ny tittel"

    # The item keeps what it was raised with: the text in between is not the
    # one the translation was written from
    retitle(c, "Nyere tittel")
    assert %{source_previous: nil} = open_review(c, "title")
  end

  test "work opened again after an undo keeps its previous text", c do
    retitle(c, "Ny tittel")

    {:ok, revision} =
      Brando.Revisions.create_revision(
        Repo.get!(Article, c.target.id) |> Repo.preload(Brando.Blueprint.preloads_for(Article)),
        c.user
      )

    {:ok, result} = Translations.save_work(Article, c.target.id, %{texts: %{"title" => "New title"}}, c.user)
    assert [%{path: "title", source_previous: "Tittel"}] = result.resolved

    {:ok, _} = Brando.Revisions.set_entry_to_revision(Article, c.target.id, revision.revision, c.user)
    {:ok, _} = Translations.reopen_work(Article, c.target.id, result.resolved)

    assert %{source_previous: "Tittel"} = open_review(c, "title")
  end

  test "making a translation the source resets every member's texts to it", c do
    {:ok, _} = Translations.transfer_source(Article, c.target.id, c.user)

    assert member(c.source).baseline_texts["title"] == "Tittel"
    assert member(c.target).baseline_texts == %{}
    assert member(c.target).baseline == %{}
  end

  test "a new source that kept no texts is left with none", c do
    from(m in Member, where: m.entry_id == ^c.target.id and m.entry_type == ^to_string(Article))
    |> Repo.update_all(set: [baseline_texts: %{}])

    {:ok, _} = Translations.transfer_source(Article, c.target.id, c.user)

    assert member(c.target).baseline_texts == %{}
    assert member(c.source).baseline_texts["title"] == "Tittel"
  end

  test "the listing and a member's lookup leave the source's texts unread", c do
    sql =
      queries(fn ->
        Translations.listing_status(Article, [%{id: c.source.id}, %{id: c.target.id}])
        Translations.get_member(Article, c.target.id)
        Translations.list_members(Translations.get_member(Article, c.target.id).group_id)
      end)

    assert sql != []
    refute Enum.any?(sql, &(&1 =~ "baseline_texts"))
  end

  test "a sync of a member looked up by get_member reads its kept texts", c do
    member = member(c.target)

    from(m in Member, where: m.id == ^member.id)
    |> Repo.update_all(
      set: [
        baseline: Map.put(member.baseline, "title", "stale"),
        baseline_texts: Map.put(member.baseline_texts, "title", "Gammel tittel")
      ]
    )

    {:ok, _} = Translations.target_saved(Article, c.target.id)

    assert %{source_previous: "Gammel tittel"} = open_review(c, "title")
    assert member(c.target).baseline_texts["title"] == "Tittel"
  end
end
