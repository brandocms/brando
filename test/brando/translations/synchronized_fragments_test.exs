defmodule Brando.Translations.SynchronizedFragmentsTest do
  # Fragments configured as synchronized translations, as pages are
  # (`config :brando, Brando.Pages.Fragment, translatable: [...]`). Not async:
  # the tests set the application's Fragment and Page configuration.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Translations
  alias Brando.Translations.Pairing

  setup do
    put_test_env(Fragment, translatable: [mode: :synchronized])
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "<p>{% ref refs.body %}</p>",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    %{user: user, module: module}
  end

  defp fragment!(c, language, text, attrs \\ []) do
    fragment =
      Factory.insert(
        :fragment,
        Keyword.merge([parent_key: "footer", key: "contact", language: language, creator: c.user], attrs)
      )

    if text, do: add_block(fragment, Fragment.Blocks, c, %{"type" => "module", "module_id" => c.module.id}, text)
    {:ok, _} = Blocks.render_entry(Fragment, fragment.id)
    fragment
  end

  defp add_block(entry, join, c, params, text \\ nil, sequence \\ 0) do
    refs =
      if text,
        do: [
          %{
            "uid" => Brando.Utils.generate_uid(),
            "name" => "body",
            "data" => %{"type" => "text", "data" => %{"text" => text}}
          }
        ],
        else: []

    params =
      Map.merge(
        %{"uid" => Brando.Utils.generate_uid(), "creator_id" => c.user.id, "source" => to_string(join), "refs" => refs},
        params
      )

    block = %Block{} |> Block.recursive_block_changeset(params, c.user) |> Repo.insert!()
    struct(join, %{entry_id: entry.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  defp load(schema, id) do
    {:ok, entry} = Brando.Blueprint.EntryQuery.get(schema, id)
    entry
  end

  defp pending(schema, entry), do: Translations.get_pending_version(schema, entry.id)
  defp payload(schema, entry), do: schema |> pending(entry) |> Translations.decode_payload()
  defp open_items(schema, entry), do: Enum.reject(pending(schema, entry).work_items, & &1.resolved_at)

  defp awaiting(schema, entry),
    do: for(%{kind: :awaiting_translation, path: path} <- open_items(schema, entry), do: path)

  # What the public site prints for the key in `language`
  defp printed(language) do
    Brando.Cache.Query.evict_all(Fragment)
    "footer" |> Pages.render_fragment("contact", language) |> Phoenix.HTML.safe_to_string()
  end

  defp same_key_count(language),
    do:
      Repo.aggregate(
        from(f in Fragment,
          where: f.parent_key == "footer" and f.key == "contact" and f.language == ^language and is_nil(f.deleted_at)
        ),
        :count
      )

  describe "a translation" do
    test "follows its source's blocks, and keeps the keys", c do
      source = fragment!(c, :no, "Kontakt oss")
      {:ok, en} = Translations.create_target(Fragment, source.id, :en, c.user)

      assert {en.parent_key, en.key, en.language} == {"footer", "contact", :en}
      # Keys are the same in every language: nothing to translate in them
      refute Enum.any?(open_items(Fragment, en), &(&1.path in ["parent_key", "key"]))
      assert Enum.any?(open_items(Fragment, en), &(&1.kind == :translate and &1.path =~ ~r"^entry_blocks/"))
      assert [_] = Translations.language_versions(Fragment, load(Fragment, source.id), nil).linked

      # A block added to the source is work in the translation
      before = open_items(Fragment, en) |> Enum.map(& &1.path) |> MapSet.new()
      add_block(source, Fragment.Blocks, c, %{"type" => "module", "module_id" => c.module.id}, "Åpningstider", 1)
      Translations.source_saved(load(Fragment, source.id))

      added = for item <- open_items(Fragment, en), item.path not in before, do: item
      assert [%{kind: :translate, path: path}] = added
      assert path =~ ~r"^entry_blocks/.+/refs/body/text$"
      assert length(payload(Fragment, en).entry_blocks) == 2

      # The source's new keys follow, as a shared value
      {:ok, _} = Pages.update_fragment(source.id, %{key: "contact-us"}, c.user)
      assert payload(Fragment, en).key == "contact-us"
    end
  end

  # Edge case 1
  describe "a translation next to a fragment with the same keys" do
    setup c do
      source = fragment!(c, :no, "Kontakt oss", status: :published)
      english = fragment!(c, :en, "Get in touch", status: :published)
      %{source: source, english: english}
    end

    test "is refused before and after the two are paired, and the site prints the existing one", c do
      assert printed("en") =~ "Get in touch"
      refute "en" in Translations.missing_languages(Fragment, c.source)
      assert {:error, :language_exists} = Translations.create_target(Fragment, c.source.id, :en, c.user)
      assert {:error, :language_exists} = Translations.replace_trashed_target(Fragment, c.source.id, :en, c.user)
      assert same_key_count("en") == 1
      assert printed("en") =~ "Get in touch"

      assert [%{status: :linked}] = Pairing.apply(Fragment, Pairing.plan(Fragment))

      refute "en" in Translations.missing_languages(Fragment, c.source)
      assert {:error, :language_exists} = Translations.create_target(Fragment, c.source.id, :en, c.user)
      assert same_key_count("en") == 1
      assert printed("en") =~ "Get in touch"
      assert printed("no") =~ "Kontakt oss"
    end

    test "is refused when the source was already a group's source", c do
      {:ok, _} = Translations.enroll_source(Fragment, c.source.id, c.user)

      assert {:error, :language_exists} = Translations.create_target(Fragment, c.source.id, :en, c.user)
      assert same_key_count("en") == 1
      assert printed("en") =~ "Get in touch"
    end
  end

  # No save refuses a taken key: fragments have no unique keys, and a
  # language may hold two with the same ones (`Pairing` reports them)
  describe "a key renamed in the source" do
    test "to one an unlinked fragment holds gives the translation's language two fragments with it", c do
      source = fragment!(c, :no, "Kontakt oss", status: :published)
      {:ok, en} = Translations.create_target(Fragment, source.id, :en, c.user)
      help = fragment!(c, :en, "Help", key: "help", status: :published)

      {:ok, _} = Pages.update_fragment(source.id, %{key: "help"}, c.user)
      assert payload(Fragment, en).key == "help"
      {:ok, _} = Translations.save_work(Fragment, en.id, %{texts: %{}, acknowledged: []}, c.user)

      assert Repo.all(from f in Fragment, where: f.key == "help" and f.language == :en, select: f.id, order_by: f.id) ==
               [en.id, help.id]
    end
  end

  # Edge case 2
  describe "deleting a page with its fragments" do
    test "keeps the source of a synchronized group, and deletes nothing", c do
      page = Factory.insert(:page, uri: "kontakt", language: :no, creator: c.user)
      source = fragment!(c, :no, "Kontakt oss", page_id: page.id)
      {:ok, en} = Translations.create_target(Fragment, source.id, :en, c.user)

      assert {:error, {:fragments, :group_has_synchronized_members}} =
               Pages.delete_page(page.id, c.user, fragments: :delete)

      assert is_nil(Repo.get!(Page, page.id).deleted_at)
      assert is_nil(Repo.get!(Fragment, source.id).deleted_at)

      # As a direct delete of the fragment is refused
      assert {:error, :group_has_synchronized_members} = Pages.delete_fragment(source.id, c.user)

      {:ok, _} = Translations.make_independent(Fragment, en.id, c.user)
      assert {:ok, _} = Pages.delete_page(page.id, c.user, fragments: :delete)
      refute is_nil(Repo.get!(Fragment, source.id).deleted_at)
    end
  end

  # Edge case 3
  describe "the page of a translation" do
    setup c do
      page = Factory.insert(:page, uri: "om", title: "Om oss", language: :no, creator: c.user)
      %{page: page, source: fragment!(c, :no, "Kontakt oss", page_id: page.id)}
    end

    test "is the page's version in its language", c do
      page_en = Factory.insert(:page, uri: "about", title: "About", language: :en, creator: c.user)
      :ok = Page.Alternate.add(c.page.id, page_en.id)

      {:ok, en} = Translations.create_target(Fragment, c.source.id, :en, c.user)

      assert en.page_id == page_en.id
      assert payload(Fragment, en).page_id == page_en.id
      assert awaiting(Fragment, en) == []

      # A later sync keeps it there
      Translations.source_saved(load(Fragment, c.source.id))
      assert payload(Fragment, en).page_id == page_en.id
    end

    test "waits for the page's translation, under no page, then follows it", c do
      {:ok, en} = Translations.create_target(Fragment, c.source.id, :en, c.user)

      assert is_nil(en.page_id)
      assert awaiting(Fragment, en) == ["page/#{c.page.id}"]
      assert is_nil(payload(Fragment, en).page_id)

      page_en = Factory.insert(:page, uri: "about", title: "About", language: :en, creator: c.user)
      :ok = Page.Alternate.add(c.page.id, page_en.id)

      assert payload(Fragment, en).page_id == page_en.id
      assert awaiting(Fragment, en) == []
    end

    test "is a page already in the translation's language, as it is", c do
      page_en = Factory.insert(:page, uri: "about", title: "About", language: :en, creator: c.user)
      source = fragment!(c, :no, "Adresse", key: "address", page_id: page_en.id)

      {:ok, en} = Translations.create_target(Fragment, source.id, :en, c.user)

      assert en.page_id == page_en.id
      assert payload(Fragment, en).page_id == page_en.id
      assert awaiting(Fragment, en) == []
    end

    test "is none for a fragment with no page", c do
      source = fragment!(c, :no, "Adresse", key: "address")
      {:ok, en} = Translations.create_target(Fragment, source.id, :en, c.user)

      assert is_nil(en.page_id)
      assert is_nil(payload(Fragment, en).page_id)
      assert awaiting(Fragment, en) == []
    end
  end

  # Edge case 7
  describe "a fragment block in a synchronized page" do
    setup c do
      put_test_env(Page, translatable: [mode: :synchronized])
      fragment = fragment!(c, :no, "Kontakt oss", status: :published)
      page = Factory.insert(:page, uri: "om", title: "Om oss", language: :no, creator: c.user)
      add_block(page, Page.Blocks, c, %{"type" => "fragment", "fragment_id" => fragment.id})
      %{fragment: fragment, page: page}
    end

    defp translated_page_html(c) do
      {:ok, en} = Translations.create_target(Page, c.page.id, :en, c.user)
      page_html(en, c)
    end

    defp pending_fragment_id(en) do
      [%{block: %{fragment_id: id}}] = payload(Page, en).entry_blocks
      id
    end

    # The translation's pending version applied and rendered
    defp page_html(en, c) do
      {:ok, _} = Translations.save_work(Page, en.id, %{texts: %{}, acknowledged: []}, c.user)
      {:ok, _} = Blocks.render_entry(Page, en.id)
      Repo.get!(Page, en.id).rendered_blocks
    end

    test "embeds the fragment's version in the translation's language", c do
      english = fragment!(c, :en, "Get in touch", status: :published)
      :ok = Fragment.Alternate.add(c.fragment.id, english.id)

      html = translated_page_html(c)
      assert html =~ "Get in touch"
      refute html =~ "Kontakt oss"
    end

    test "embeds the source's fragment while it has no version in that language", c do
      html = translated_page_html(c)
      assert html =~ "Kontakt oss"
    end

    test "moves over to a version linked after the translation exists", c do
      {:ok, en} = Translations.create_target(Page, c.page.id, :en, c.user)
      assert page_html(en, c) =~ "Kontakt oss"

      english = fragment!(c, :en, "Get in touch", status: :published)
      :ok = Fragment.Alternate.add(c.fragment.id, english.id)

      html = page_html(en, c)
      assert html =~ "Get in touch"
      refute html =~ "Kontakt oss"
    end

    test "moves over when a pairing run finds the key linked by a run that stopped before the re-sync", c do
      {:ok, en} = Translations.create_target(Page, c.page.id, :en, c.user)
      english = fragment!(c, :en, "Get in touch", status: :published)

      now = NaiveDateTime.utc_now(:second)

      Repo.insert_all(Fragment.Alternate, [
        %{entry_id: c.fragment.id, linked_entry_id: english.id, inserted_at: now, updated_at: now},
        %{entry_id: english.id, linked_entry_id: c.fragment.id, inserted_at: now, updated_at: now}
      ])

      assert pending_fragment_id(en) == c.fragment.id

      assert Pairing.apply(Fragment, Pairing.plan(Fragment)) == []
      assert pending_fragment_id(en) == english.id
      assert page_html(en, c) =~ "Get in touch"
    end

    test "goes back to the source's fragment when the version is unlinked", c do
      english = fragment!(c, :en, "Get in touch", status: :published)
      :ok = Fragment.Alternate.add(c.fragment.id, english.id)
      {:ok, en} = Translations.create_target(Page, c.page.id, :en, c.user)
      assert page_html(en, c) =~ "Get in touch"

      Fragment.Alternate.delete(c.fragment.id, english.id)

      html = page_html(en, c)
      assert html =~ "Kontakt oss"
      refute html =~ "Get in touch"
    end
  end
end
