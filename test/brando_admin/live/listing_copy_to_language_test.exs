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
