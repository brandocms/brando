defmodule BrandoAdmin.Live.OptionLabelsLiveTest do
  # A page's title is data an editor sets, and a fragment's page picker lists
  # pages by title. Another admin opening the fragment sees the title as text.
  # The payload is an image with an inert marker attribute; a live one in the
  # render means the editor's markup would run in that admin's browser.
  use Brando.LiveCase

  alias Brando.Factory

  @title ~s(About<img src="x" data-marker="title">)

  setup do
    editor = Factory.insert(:random_user, role: :editor)
    page = Factory.insert(:page, title: @title, creator: editor)
    fragment = Factory.insert(:fragment, page_id: page.id, creator: editor)
    {:ok, fragment: fragment}
  end

  test "a page title with markup shows as text in a fragment's page picker", %{conn: conn, fragment: fragment} do
    {:ok, view, _html} = live(conn, "/admin/pages/fragments/update/#{fragment.id}")
    render_async(view)

    picker = "[data-select-input$='_page_id']"
    doc = view |> render() |> LazyHTML.from_fragment()

    assert markers(doc) == []
    assert doc |> LazyHTML.query("#{picker} .select-label") |> LazyHTML.text() =~ @title

    view |> element("#{picker} button.button-edit") |> render_click()
    doc = view |> render() |> LazyHTML.from_fragment()

    assert markers(doc) == []
    assert doc |> LazyHTML.query("#{picker} .options-option") |> LazyHTML.text() =~ @title
  end

  defp markers(doc), do: doc |> LazyHTML.query("[data-marker]") |> LazyHTML.attribute("data-marker")
end
