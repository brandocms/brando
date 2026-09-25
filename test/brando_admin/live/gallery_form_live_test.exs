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

  test "the technical settings are shown to superusers only", %{conn: conn} do
    gallery = Factory.insert(:gallery)
    config_target = "input[name='gallery[config_target]']"

    {:ok, view, _html} = live(conn, "/admin/assets/galleries/update/#{gallery.id}")
    assert has_element?(view, config_target)

    editor = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)
    {:ok, view, _html} = live(conn, "/admin/assets/galleries/update/#{gallery.id}")
    refute has_element?(view, config_target)
    assert render(view) =~ "Images and videos"
  end
end
