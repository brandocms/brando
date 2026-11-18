defmodule Brando.Translations.NewTranslationTest do
  # A new synchronized translation starts with every text it copied from the
  # source marked to translate (#3618). Not async: the Page tests set the
  # application's Page configuration.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations
  alias Brando.Translations.Sync

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
        %{
          title: "Tittel",
          slug: "tittel",
          language: "no",
          status: "published",
          year: 2020,
          subtitle: "",
          items: [%{label: "Første punkt", link: "/a"}]
        },
        user
      )

    text = TranslationFixtures.add_block(source, module, user, "Første avsnitt", 0)
    rich = add_block(source, module, user, 1)

    %{user: user, module: module, source: source, text_uid: text.uid, rich_uid: rich.uid}
  end

  # A block with a picture, a string, an empty string and a URL link
  defp add_block(article, module, user, sequence) do
    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Article.Blocks),
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "photo",
          "data" => %{"type" => "picture", "data" => %{"title" => "Bildetittel", "alt" => "Bilde", "credits" => ""}}
        }
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()

    # Inserted as they are: the module defines no variables
    for {var, index} <-
          Enum.with_index([
            %Var{key: "heading", type: :string, value: "Overskrift"},
            %Var{key: "empty", type: :string, value: ""},
            %Var{key: "cta", type: :link, link_type: :url, value: "/no/om-oss", link_text: "Les mer"}
          ]),
        do: Repo.insert!(%{var | label: %{"en" => var.key}, block_id: block.id, sequence: index})

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  defp load(id) do
    {:ok, entry} = SyncTest.get_article(%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(Article)})
    entry
  end

  defp open_items(schema \\ Article, target) do
    case Translations.get_pending_version(schema, target.id) do
      nil ->
        []

      version ->
        version.work_items |> Enum.filter(&is_nil(&1.resolved_at)) |> Enum.map(&{&1.kind, &1.path}) |> Enum.sort()
    end
  end

  defp item(target, path) do
    Enum.find(Translations.get_pending_version(Article, target.id).work_items, &(&1.path == path))
  end

  defp set_text(article_id, text) do
    [join | _] = load(article_id).entry_blocks
    [ref] = Repo.preload(join.block, :refs, force: true).refs
    ref |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: text}}) |> Repo.update!()
  end

  defp payload_body(target) do
    [join | _] =
      Translations.get_pending_version(Article, target.id) |> Translations.decode_payload() |> Map.get(:entry_blocks)

    hd(join.block.refs).data.data.text
  end

  defp body_path(c), do: "entry_blocks/#{c.text_uid}/refs/body/text"

  defp expected(c) do
    rich = "entry_blocks/#{c.rich_uid}"

    Enum.sort([
      {:translate, "title"},
      {:translate, body_path(c)},
      {:translate, rich <> "/refs/photo/title"},
      {:translate, rich <> "/refs/photo/alt"},
      {:translate, rich <> "/vars/heading/value"},
      {:translate, rich <> "/vars/cta/link_text"},
      {:translate, rich <> "/vars/cta/url"},
      {:translate, "items/#{hd(load(c.source.id).items).uid}/label"},
      {:translate, "items/#{hd(load(c.source.id).items).uid}/link"}
    ])
  end

  test "creating a translation marks every copied text to translate, and no empty one", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

    # The empty subtitle, picture credits and variable are left out
    assert open_items(target) == expected(c)
    assert item(target, "title").source_digest == Sync.digest("Tittel")

    # The listing counts them
    status = Translations.listing_status(Article, [load(c.source.id)])
    assert %{counts: %{translate: count}} = Enum.find(status[c.source.id], &(&1.language == "en"))
    assert count == length(expected(c))
  end

  test "a synchronized page marks its meta texts and variables too", c do
    put_test_env(Page, translatable: [mode: :synchronized])

    source =
      Factory.insert(:page,
        title: "Om oss",
        uri: "om-oss",
        language: :no,
        creator: c.user,
        meta_title: "Om oss | Firma",
        meta_description: ""
      )

    Repo.insert!(%Var{type: :string, key: "tagline", value: "Hei", label: %{"en" => "Tagline"}, page_id: source.id})

    {:ok, target} = Translations.create_target(Page, source.id, :en, c.user)
    items = open_items(Page, target)

    assert {:translate, "title"} in items
    assert {:translate, "meta_title"} in items
    assert {:translate, "vars/tagline/value"} in items
    refute Enum.any?(items, fn {_kind, path} -> path == "meta_description" end)
    assert Enum.all?(items, &match?({:translate, _}, &1))
  end

  test "translating an item, or marking it reviewed, resolves it", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    version = Translations.get_pending_version(Article, target.id)
    picture_alt = "entry_blocks/#{c.rich_uid}/refs/photo/alt"

    # The editor translates the title and keeps the picture's alt text as it is.
    {:ok, _} =
      target.id
      |> load()
      |> Article.changeset(%{title: "Title"}, c.user)
      |> SyncTest.update_article(c.user, editor_review: true)

    assert {:ok, %{open: open}} =
             Translations.target_saved(Article, target.id, %{version_id: version.id, acknowledged: [picture_alt]})

    assert open_items(target) == expected(c) -- [{:translate, "title"}, {:translate, picture_alt}]
    assert open == length(expected(c)) - 2
  end

  describe "a later source save" do
    test "keeps an untranslated text to translate, raised against the new source text", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

      for text <- ["Første avsnitt, endret", "Første avsnitt, endret igjen"] do
        set_text(c.source.id, text)
        Translations.source_saved(load(c.source.id))

        assert open_items(target) == expected(c)
        assert item(target, body_path(c)).source_digest == Sync.digest(text)
        # The form gets the source's new text to translate, not the old copy
        assert payload_body(target) == text
      end
    end

    test "text written past the editor is the translation's own: a change in the source asks for review", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

      # A save that is not the editor's resolves nothing
      set_text(target.id, "First paragraph")
      Translations.target_saved(Article, target.id)
      assert {:translate, body_path(c)} in open_items(target)

      set_text(c.source.id, "Første avsnitt, endret")
      Translations.source_saved(load(c.source.id))

      assert {:review, body_path(c)} in open_items(target)
      refute {:translate, body_path(c)} in open_items(target)
      assert payload_body(target) == "First paragraph"
    end

    test "an editor who translated while the source changed the text is asked to review it", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      loaded = Translations.get_pending_version(Article, target.id)

      # The source changes the text while the editor translates the old one
      set_text(c.source.id, "Første avsnitt, endret")
      Translations.source_saved(load(c.source.id))
      set_text(target.id, "First paragraph")

      assert {:ok, %{stale: true}} = Translations.target_saved(Article, target.id, %{version_id: loaded.id})

      assert {:review, body_path(c)} in open_items(target)
      refute {:translate, body_path(c)} in open_items(target)
      assert payload_body(target) == "First paragraph"
    end

    test "still asks for review of a text that was translated", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      version = Translations.get_pending_version(Article, target.id)

      set_text(target.id, "First paragraph")
      Translations.target_saved(Article, target.id, %{version_id: version.id, acknowledged: []})
      refute {:translate, body_path(c)} in open_items(target)

      set_text(c.source.id, "Første avsnitt, endret")
      Translations.source_saved(load(c.source.id))

      assert {:review, body_path(c)} in open_items(target)
      refute {:translate, body_path(c)} in open_items(target)
    end

    test "keeps a text marked reviewed resolved until the source changes it", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      version = Translations.get_pending_version(Article, target.id)

      Translations.target_saved(Article, target.id, %{version_id: version.id, acknowledged: [body_path(c)]})
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.user)

      refute Enum.any?(open_items(target), fn {_kind, path} -> path == body_path(c) end)
    end
  end

  test "mark_translate: false creates the translation with nothing to translate", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user, mark_translate: false)

    assert open_items(target) == []
    assert %{role: :target, synchronized: true} = Translations.get_member(Article, target.id)
  end

  test "a translation that already exists gets no marks for its copied text", c do
    # As every translation was created before #3618
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user, mark_translate: false)

    # Neither a source save nor its own recompute marks the text it holds
    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.user)
    Translations.target_saved(Article, target.id)

    assert open_items(target) == [{:shared_update, "year"}]
  end
end
