defmodule BrandoAdmin.ListingCopyToLanguageTest do
  # The Pages listing's "Duplicate to [NO]" and "Translate to [NO]" copy a page
  # into another language. The Index page is the common case where that
  # language already has a page at the same URI: the copy used to hit the
  # unique index on (uri, language), raise, and take the listing down.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Pages.Page

  @path "/admin/pages"

  setup do
    no_index = Factory.insert(:page, title: "Indeks", uri: "index", language: :no)
    en_index = Factory.insert(:page, title: "Index", uri: "index", language: :en)
    %{no_index: no_index, en_index: en_index}
  end

  defp open_listing(conn) do
    {:ok, view, _html} = live(conn, @path)
    await_selector(view, ".list-row")
    view
  end

  defp action(kind, entry), do: "#action_default_#{kind}_entry_to_lang_#{entry.id}_lang_no"

  defp norwegian_pages, do: Repo.all(from p in Page, where: p.language == :no, order_by: p.id)

  test "Duplicate to a language that uses the page's URI copies it to a free URI", c do
    view = open_listing(c.conn)

    view |> element(action(:duplicate, c.en_index)) |> render_click()

    assert [_, copy] = norwegian_pages()
    assert copy.uri == "index-2"
    assert_redirect(view, "/admin/pages/update/#{copy.id}", 1_000)
    assert Brando.Translations.alternate_languages(Page, c.en_index.id) == ["no"]

    # The copy opens in the editor with its address in the other language
    {_editor, html} = live_form(c.conn, "/admin/pages/update/#{copy.id}")
    assert html =~ "/no/index-2"
  end

  test "Duplicate to a language links the related entries' versions in it", c do
    alias Brando.SyncTest
    alias Brando.SyncTest.Article

    article = fn title, slug ->
      {:ok, article} =
        SyncTest.create_article(%{title: title, slug: slug, language: "no", status: "published"}, c.current_user)

      article
    end

    identifier_of = fn entry -> Repo.get_by!(Brando.Content.Identifier, schema: Article, entry_id: entry.id) end

    source = article.("Example Hotel", "example-hotel")
    hotel = article.("Example Hotel Annex", "example-hotel-annex")
    {:ok, hotel_en} = Brando.Translations.create_target(Article, hotel.id, :en, c.current_user)
    Repo.insert!(%Article.RelatedEntriesIdentifier{parent_id: source.id, identifier_id: identifier_of.(hotel).id})

    {:ok, view, _html} = live(c.conn, "/admin/articles")
    render_click(view, "duplicate_entry_to_language", %{"id" => "#{source.id}", "language" => "en"})

    assert [copy] =
             Repo.all(from a in Article, where: a.language == :en and a.id != ^hotel_en.id, preload: :related_entries)

    identifier_id = identifier_of.(hotel_en).id
    assert [%{identifier_id: ^identifier_id}] = copy.related_entries
  end

  test "Duplicate selected to a language links entries copied together, and counts the links left out", c do
    alias Brando.SyncTest
    alias Brando.SyncTest.Article

    article = fn title, slug ->
      {:ok, article} =
        SyncTest.create_article(%{title: title, slug: slug, language: "no", status: "published"}, c.current_user)

      article
    end

    identifier_of = fn entry -> Repo.get_by!(Brando.Content.Identifier, schema: Article, entry_id: entry.id) end

    hotel = article.("Example Hotel", "example-hotel")
    annex = article.("Example Hotel Annex", "example-hotel-annex")
    spa = article.("Example Hotel Spa", "example-hotel-spa")

    # The hotel links the annex, copied with it, and the spa, which is not
    # copied and has no English version; so does its author's link.
    for {target, sequence} <- [{annex, 0}, {spa, 1}] do
      Repo.insert!(%Article.RelatedEntriesIdentifier{
        parent_id: hotel.id,
        identifier_id: identifier_of.(target).id,
        sequence: sequence
      })
    end

    author =
      Repo.insert!(%SyncTest.ArticleAuthor{
        article_id: hotel.id,
        name: "Example Author",
        links: [%SyncTest.ArticleAuthorLink{label: "Example Hotel"}]
      })

    Repo.insert!(%SyncTest.ArticleAuthorLink.RelatedEntriesIdentifier{
      parent_id: hd(author.links).id,
      identifier_id: identifier_of.(annex).id
    })

    Brando.endpoint().subscribe("user:#{c.current_user.id}")
    {:ok, view, _html} = live(c.conn, "/admin/articles")

    render_click(view, "duplicate_selected_to_language", %{
      "ids" => Jason.encode!([hotel.id, annex.id]),
      "language" => "en"
    })

    copies = Repo.all(from a in Article, where: a.language == :en, order_by: a.id, preload: [:related_entries])
    assert [hotel_en, annex_en] = copies
    annex_en_identifier = identifier_of.(annex_en).id

    assert [%{identifier_id: ^annex_en_identifier}] = hotel_en.related_entries

    [link] = Repo.preload(hotel_en, author: [links: :related_entries]).author.links
    assert [%{identifier_id: ^annex_en_identifier}] = link.related_entries

    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "1 link" <> _}}, 2_000
  end

  test "a language the page already has is not offered, and is refused if asked for", c do
    Brando.AIStub.configure()
    Page.Alternate.add(c.en_index.id, c.no_index.id)
    Brando.endpoint().subscribe("user:#{c.current_user.id}")

    view = open_listing(c.conn)

    refute has_element?(view, action(:duplicate, c.en_index))
    refute has_element?(view, action(:translate, c.en_index))

    render_click(view, "duplicate_entry_to_language", %{"id" => "#{c.en_index.id}", "language" => "no"})
    assert_receive %Phoenix.Socket.Broadcast{event: "toast"}

    render_click(view, "translate_entry_to_language", %{"id" => "#{c.en_index.id}", "language" => "no"})
    await_selector(view, ".translation-dialog-error")

    assert Process.alive?(view.pid)
    assert Enum.map(norwegian_pages(), & &1.id) == [c.no_index.id]
  end

  test "Translate to a language that uses the page's URI translates a copy at a free URI", c do
    Brando.AIStub.configure()

    Brando.AIStub.reply(fn prompt ->
      ~r/^(\d+): .*$/m
      |> Regex.scan(prompt, capture: :all_but_first)
      |> Enum.map_join("\n", fn [n] -> "#{n}: Indeks" end)
    end)

    view = open_listing(c.conn)

    view |> element(action(:translate, c.en_index)) |> render_click()
    await_selector(view, ".translation-dialog-link", 5_000)

    assert [_, copy] = norwegian_pages()
    assert {copy.uri, copy.title} == {"index-2", "Indeks"}
    refute has_element?(view, ".translation-dialog-error")
  end
end
