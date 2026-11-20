defmodule Brando.Translations.SourcePreviousTransferTest do
  # A review's previous text is the former source's: when another translation
  # becomes the source, the reviews still open are read against it, and the
  # text in the former source's language goes.
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias Brando.Translations.Member
  alias Brando.Translations.Sync

  setup do
    user = Factory.insert(:random_user)

    {:ok, source} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "tittel-#{System.unique_integer([:positive])}", language: "no", status: "published"},
        user
      )

    {:ok, english} = Translations.create_target(Article, source.id, :en, user, mark_translate: false)

    %{user: user, source: source, english: english, other: other_target(source, english, user)}
  end

  # The test configuration has two languages: the group's third member, a
  # translation that stays one when the source moves, is an English article
  # enrolled as a German translation
  defp other_target(source, english, user) do
    {:ok, other} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "other-#{System.unique_integer([:positive])}", language: "en", status: "published"},
        user
      )

    member = Translations.get_member(Article, english.id)
    {:ok, loaded} = Translations.load_entry(Article, source.id)
    uids = Translations.module_uids([loaded], Article)

    Repo.insert!(%Member{
      group_id: member.group_id,
      entry_type: member.entry_type,
      entry_id: other.id,
      language: "de",
      role: :target,
      synchronized: true,
      last_synced_generation: member.last_synced_generation,
      baseline: Sync.baseline_for(loaded, Article, nil, uids),
      baseline_texts: Sync.baseline_texts_for(loaded, Article, nil, uids)
    })

    other
  end

  defp open_review(entry, path) do
    case Translations.get_pending_version(Article, entry.id) do
      nil -> []
      version -> version.work_items
    end
    |> Enum.find(&(&1.kind == :review and &1.path == path and is_nil(&1.resolved_at)))
  end

  test "making a translation the source drops the previous texts of the reviews still open", c do
    {:ok, _} = SyncTest.update_article(c.source.id, %{title: "Ny tittel"}, c.user)
    assert %{source_previous: "Tittel"} = open_review(c.other, "title")

    {:ok, _} = Translations.transfer_source(Article, c.english.id, c.user)

    # The review stays open, read against the English source now
    assert %{source_previous: nil} = open_review(c.other, "title")

    # and a change by the new source does not bring the Norwegian text back
    {:ok, _} = SyncTest.update_article(c.english.id, %{title: "Newer English title"}, c.user)
    assert %{source_previous: nil} = open_review(c.other, "title")
  end
end
