defmodule BrandoAdmin.GalleryFormLiveTest do
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Pages.Page

  test "a gallery in use opens, listing the entries that use it", %{conn: conn} do
    page = Factory.insert(:page, title: "Om oss")
    Brando.Content.create_identifier(Page, page)
    gallery = Factory.insert(:gallery)

    source = "Elixir.Brando.Pages.Page.Blocks"
    block = Brando.Repo.insert!(%Block{type: :module, source: source, uid: "galleryblock00000000001"})
    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    Factory.insert(:ref, block_id: block.id, gallery_id: gallery.id)

    {:ok, _view, html} = live(conn, "/admin/assets/galleries/update/#{gallery.id}")
    assert html =~ "Om oss"
  end
end
