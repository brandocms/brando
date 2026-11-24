defmodule Brando.Translations.DeleteSourceTest do
  # Deleting the source of synchronized translations (#3926): with its
  # translations, which go to the trash with it and come back with it, or
  # keeping them, with one of them the source or all independent. Each in
  # one transaction, against the group as the editor confirmed it. Not async:
  # pages are made synchronized through the application env.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Authorization.Boundary
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias Brando.Translations.Group
  alias Brando.Translations.Member

  setup do
    put_test_env(Page, translatable: [mode: :synchronized])
    put_test_env(Fragment, translatable: [mode: :synchronized])
    put_test_env(:tenancy_mode, :none)
    user = Factory.insert(:random_user, role: :superuser)
    source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, status: :published, creator: user)
    {:ok, english} = Translations.create_target(Page, source.id, :en, user)
    %{user: user, source: source, english: english}
  end

  # A second translation in a language the test app lacks: a page in
  # English joined to the group as German, as the listing reads it
  defp join_as_german(c, attrs \\ []) do
    page =
      Factory.insert(
        :page,
        Keyword.merge([title: "Über uns", uri: "uber-uns", language: :en, status: :draft, creator: c.user], attrs)
      )

    %{group_id: group_id} = Translations.get_member(Page, c.source.id)

    Repo.insert!(%Member{
      group_id: group_id,
      entry_type: to_string(Page),
      entry_id: page.id,
      language: "de",
      role: :target,
      synchronized: true
    })

    page
  end

  defp fingerprint(schema, id), do: Translations.source_group(schema, id).fingerprint
  defp trashed_at(schema, id), do: Repo.get!(schema, id).deleted_at
  defp member(schema, id), do: Translations.get_member(schema, id)

  defp deleted_lines(schema, id) do
    type = to_string(schema)
    Repo.aggregate(from(e in Event, where: e.schema == ^type and e.entry_id == ^id and e.action == :trashed), :count)
  end

  defp delete_with(c, opts \\ []),
    do: Translations.delete_with_translations(Page, c.source.id, fingerprint(Page, c.source.id), c.user, opts)

  describe "the group as the dialog shows it" do
    test "lists the synchronized translations apart from the independent versions", c do
      german = join_as_german(c)
      {:ok, _} = Translations.make_independent(Page, german.id, c.user)

      assert %{source: %{entry: %{id: source_id}}, translations: [english], independent: [independent]} =
               Translations.source_group(Page, c.source.id)

      assert source_id == c.source.id
      assert %{entry: %{id: english_id}, language: "en", published: false, in_trash: false} = english
      assert english_id == c.english.id
      assert independent.entry.id == german.id
    end

    test "is nil for a translation, and for a source with only independent versions", c do
      assert Translations.source_group(Page, c.english.id) == nil
      {:ok, _} = Translations.make_independent(Page, c.english.id, c.user)
      assert Translations.source_group(Page, c.source.id) == nil
    end
  end

  describe "with its translations" do
    test "trashes the group at the source's deleted_at, a line each, and a restore of the source brings it back",
         c do
      german = join_as_german(c, status: :published)

      assert {:ok, %{source: _, translations: [_, _]}} = delete_with(c)

      at = trashed_at(Page, c.source.id)
      assert %DateTime{} = at
      assert trashed_at(Page, c.english.id) == at
      assert trashed_at(Page, german.id) == at
      assert %{role: :target, synchronized: true} = member(Page, c.english.id)
      assert Enum.map([c.source.id, c.english.id, german.id], &deleted_lines(Page, &1)) == [1, 1, 1]

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Boundary.restore(c.user, Repo.get!(Page, c.source.id))
        %{group_id: group_id} = member(Page, c.source.id)
        assert_enqueued(worker: Brando.Worker.TranslationSync, args: %{group_id: group_id})
      end)

      assert Enum.map([c.source.id, c.english.id, german.id], &trashed_at(Page, &1)) == [nil, nil, nil]
    end

    test "leaves a translation trashed before on its own, and one trashed in that same second", c do
      german = join_as_german(c)
      {:ok, _} = Pages.delete_page(german.id, c.user)
      german_at = trashed_at(Page, german.id)

      # The English one trashed on its own in the second the group is
      at = DateTime.add(german_at, 5)
      {:ok, _} = Brando.SoftDelete.Repo.at(at, fn -> Pages.delete_page(c.english.id, c.user) end)

      assert {:ok, %{translations: []}} = Brando.SoftDelete.Repo.at(at, fn -> delete_with(c) end)

      assert trashed_at(Page, c.source.id) == at
      assert trashed_at(Page, german.id) == german_at
      assert trashed_at(Page, c.english.id) == DateTime.add(at, -1)
      assert deleted_lines(Page, c.english.id) == 1

      assert {:ok, _} = Boundary.restore(c.user, Repo.get!(Page, c.source.id))
      assert trashed_at(Page, c.english.id)
      assert trashed_at(Page, german.id) == german_at
    end

    test "deletes nothing when the group changed since the dialog showed it", c do
      shown = fingerprint(Page, c.source.id)

      # A draft published meanwhile
      {:ok, _} = Pages.update_page(c.english.id, %{status: :published}, c.user)

      assert {:error, :group_changed} = Translations.delete_with_translations(Page, c.source.id, shown, c.user)
      assert trashed_at(Page, c.source.id) == nil

      # A language added meanwhile
      shown = fingerprint(Page, c.source.id)
      join_as_german(c)
      assert {:error, :group_changed} = Translations.delete_with_translations(Page, c.source.id, shown, c.user)

      # The source role moved meanwhile
      shown = fingerprint(Page, c.source.id)
      {:ok, _} = Translations.transfer_source(Page, c.english.id, c.user)
      assert {:error, :group_changed} = Translations.delete_with_translations(Page, c.source.id, shown, c.user)
      assert Enum.map([c.source.id, c.english.id], &trashed_at(Page, &1)) == [nil, nil]
    end

    test "a refusal on the second translation deletes nothing", c do
      german = join_as_german(c)
      # The German page's fragment is the source of a translation: the
      # fragments can't go to the trash with it
      fragment = Factory.insert(:fragment, page_id: german.id, key: "footer", language: :no, creator: c.user)
      {:ok, _} = Translations.create_target(Fragment, fragment.id, :en, c.user)

      assert {:error, {:translation, %Page{id: id}, {:fragments, :group_has_synchronized_members}}} =
               delete_with(c, source_args: [[fragments: :delete]], translation_args: [[fragments: :delete]])

      assert id == german.id
      assert Enum.map([c.source.id, c.english.id, german.id], &trashed_at(Page, &1)) == [nil, nil, nil]
      assert deleted_lines(Page, c.english.id) == 0
    end

    test "a type without a trash deletes them for good, and its group goes", c do
      {:ok, source} = SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published"}, c.user)
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)
      %{group_id: group_id} = member(Article, source.id)

      assert {:ok, %{translations: [_]}} =
               Translations.delete_with_translations(Article, source.id, fingerprint(Article, source.id), c.user)

      assert Repo.get(Article, source.id) == nil
      assert Repo.get(Article, target.id) == nil
      assert Repo.get(Group, group_id) == nil
    end
  end

  describe "keeping its translations" do
    test "with a new source, the others follow it, and the old source is a translation of it in the trash", c do
      german = join_as_german(c)

      assert {:ok, %{translations: []}} =
               Translations.delete_keeping_translations(
                 Page,
                 c.source.id,
                 to_string(c.english.id),
                 fingerprint(Page, c.source.id),
                 c.user
               )

      assert %{role: :source} = member(Page, c.english.id)
      assert %{role: :target, synchronized: true} = member(Page, german.id)
      assert %{role: :target, synchronized: true} = member(Page, c.source.id)
      assert trashed_at(Page, c.source.id)
      assert trashed_at(Page, c.english.id) == nil

      # Restored, it is a translation as any other in the trash
      assert {:ok, _} = Boundary.restore(c.user, Repo.get!(Page, c.source.id))
      assert %{role: :target, synchronized: true} = member(Page, c.source.id)
    end

    test "made independent, every translation stays outside synchronization", c do
      german = join_as_german(c)

      assert {:ok, _} =
               Translations.delete_keeping_translations(Page, c.source.id, nil, fingerprint(Page, c.source.id), c.user)

      assert %{synchronized: false} = member(Page, c.english.id)
      assert %{synchronized: false} = member(Page, german.id)
      assert trashed_at(Page, c.source.id)
      assert Enum.map([c.english.id, german.id], &trashed_at(Page, &1)) == [nil, nil]
    end

    test "a translation in the trash stays there, made independent, under either choice", c do
      german = join_as_german(c)
      {:ok, _} = Pages.delete_page(german.id, c.user)
      german_at = trashed_at(Page, german.id)

      assert {:ok, _} =
               Translations.delete_keeping_translations(
                 Page,
                 c.source.id,
                 c.english.id,
                 fingerprint(Page, c.source.id),
                 c.user
               )

      assert %{synchronized: false} = member(Page, german.id)
      assert trashed_at(Page, german.id) == german_at
    end

    test "a successor from another group, or in the trash, is refused, and nothing changes", c do
      other = Factory.insert(:page, title: "Annen", uri: "annen", language: :no, creator: c.user)
      {:ok, other_target} = Translations.create_target(Page, other.id, :en, c.user)

      assert {:error, :not_a_synchronized_target} =
               Translations.delete_keeping_translations(
                 Page,
                 c.source.id,
                 other_target.id,
                 fingerprint(Page, c.source.id),
                 c.user
               )

      german = join_as_german(c)
      {:ok, _} = Pages.delete_page(german.id, c.user)

      assert {:error, :not_a_synchronized_target} =
               Translations.delete_keeping_translations(
                 Page,
                 c.source.id,
                 german.id,
                 fingerprint(Page, c.source.id),
                 c.user
               )

      assert %{role: :source} = member(Page, c.source.id)
      assert %{role: :target} = member(Page, other_target.id)
      assert trashed_at(Page, c.source.id) == nil
    end

    test "a page delete refused at the end leaves membership and the trash as they were", c do
      german = join_as_german(c)
      {:ok, _} = Pages.delete_page(german.id, c.user)

      # One of the page's fragments is the source of a translation: deleting
      # the fragments with the page is refused, after the detaches
      fragment = Factory.insert(:fragment, page_id: c.source.id, key: "footer", language: :no, creator: c.user)
      {:ok, _} = Translations.create_target(Fragment, fragment.id, :en, c.user)

      assert {:error, {:fragments, :group_has_synchronized_members}} =
               Translations.delete_keeping_translations(
                 Page,
                 c.source.id,
                 nil,
                 fingerprint(Page, c.source.id),
                 c.user,
                 source_args: [[fragments: :delete]]
               )

      assert %{role: :source} = member(Page, c.source.id)
      assert %{synchronized: true} = member(Page, c.english.id)
      assert %{synchronized: true} = member(Page, german.id)
      assert trashed_at(Page, c.source.id) == nil
      assert trashed_at(Page, german.id)
    end
  end

  describe "with groups authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      on_exit(fn -> Boundary.put_scope(nil) end)
      {:ok, _} = Brando.Authorization.Migration.run()
      :ok
    end

    test "a page delete refused at the end leaves membership as it was", c do
      fragment = Factory.insert(:fragment, page_id: c.source.id, key: "footer", language: :no, creator: c.user)
      {:ok, _} = Translations.create_target(Fragment, fragment.id, :en, c.user)

      assert {:error, {:fragments, :group_has_synchronized_members}} =
               Translations.delete_keeping_translations(
                 Page,
                 c.source.id,
                 nil,
                 fingerprint(Page, c.source.id),
                 c.user,
                 source_args: [[fragments: :delete]]
               )

      assert %{synchronized: true} = member(Page, c.english.id)
      assert trashed_at(Page, c.source.id) == nil
    end

    test "deletes the group, and restores it", c do
      assert {:ok, %{translations: [_]}} = delete_with(c)
      assert trashed_at(Page, c.english.id) == trashed_at(Page, c.source.id)

      assert {:ok, _} = Boundary.restore(c.user, Repo.get!(Page, c.source.id))
      assert trashed_at(Page, c.english.id) == nil
    end
  end

  describe "restoring" do
    setup c do
      {:ok, _} = delete_with(c)
      :ok
    end

    test "a translation on its own is refused while its source is in the trash", c do
      assert {:error, {:source_in_trash, %Page{id: source_id}}} =
               Boundary.restore(c.user, Repo.get!(Page, c.english.id))

      assert source_id == c.source.id
      assert trashed_at(Page, c.english.id)
    end

    test "a translation deleted for good meanwhile leaves the rest to come back", c do
      german_at = trashed_at(Page, c.english.id)
      assert :ok = Brando.SoftDelete.Query.purge_entry(Page, c.english.id, german_at, c.user)

      assert {:ok, _} = Boundary.restore(c.user, Repo.get!(Page, c.source.id))
      assert trashed_at(Page, c.source.id) == nil
    end

    test "a translation whose address is taken meanwhile leaves the whole group in the trash", c do
      Factory.insert(:page, title: "Annen", uri: "om-oss", language: :en, creator: c.user)
      # The English translation's address, as it was before the trash
      english = Repo.get!(Page, c.english.id)
      Repo.update_all(from(p in Page, where: p.id == ^english.id), set: [uri: "om-oss$$$abc"])

      assert {:error, {:translation, %Page{id: id}, _reason}} =
               Boundary.restore(c.user, Repo.get!(Page, c.source.id))

      assert id == c.english.id
      assert trashed_at(Page, c.source.id)
      assert trashed_at(Page, c.english.id)
    end
  end
end
