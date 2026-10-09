defmodule BrandoAdmin.ImageSweepLiveTest do
  # The image library's "Sort by use" (BrandoAdmin.Images.Sweep) and the
  # "Not in use" filter's delete-all.
  use Brando.LiveCase

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Images.Image
  alias Brando.Media.Folder
  alias Brando.Pages.Page
  alias Brando.Repo
  alias BrandoAdmin.Images.FolderBrowser

  setup do
    folder_id = FolderBrowser.folder_id_for("images/site/default")
    [used, unused] = for _ <- 1..2, do: Factory.insert(:image, folder_id: folder_id, status: :processed)

    page = Factory.insert(:page, title: "About us", uri: "about-us", language: "en")
    Brando.Content.create_identifier(Page, page)
    source = "Elixir.Brando.Pages.Page.Blocks"
    block = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    Factory.insert(:ref, block_id: block.id, image_id: used.id)

    %{folder_id: folder_id, used: used, unused: unused}
  end

  defp folder_of(image), do: Repo.one(from i in Image, where: i.id == ^image.id, select: i.folder_id)

  test "previews the folders, moves the images and undoes it", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, "/admin/assets/images?filter:folder_id=#{c.folder_id}")

    html = view |> element("button[phx-click=sweep_open]") |> render_click()
    assert html =~ "About us"
    assert html =~ ~s(name="name[pages/about-us]")

    html = view |> form("#image-sweep-form") |> render_submit()
    assert html =~ "media-sweep-result"
    assert Repo.get!(Folder, folder_of(c.used)).path == "site/default/pages/about-us"
    assert folder_of(c.unused) == c.folder_id

    view |> element("button[phx-click=sweep_undo]") |> render_click()
    assert folder_of(c.used) == c.folder_id
    refute Repo.get_by(Folder, path: "site/default/pages/about-us")
  end

  test "a renamed folder is used, and an unchecked entry stays", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, "/admin/assets/images?filter:folder_id=#{c.folder_id}")
    view |> element("button[phx-click=sweep_open]") |> render_click()

    view
    |> form("#image-sweep-form", %{"name" => %{"pages/about-us" => "sider/om-oss"}})
    |> render_submit()

    assert Repo.get!(Folder, folder_of(c.used)).path == "site/default/sider/om-oss"

    view |> element("button[phx-click=sweep_undo]") |> render_click()
    view |> element("button[phx-click=sweep_open]") |> render_click()

    view
    |> form("#image-sweep-form", %{"include" => %{"pages/about-us" => "false"}})
    |> render_submit()

    assert folder_of(c.used) == c.folder_id
  end

  test "the unused filter offers to delete every unused image in the folder", %{conn: conn} = c do
    {:ok, _view, html} = live(conn, "/admin/assets/images?filter:folder_id=#{c.folder_id}")
    refute html =~ "delete_unused"

    {:ok, view, html} = live(conn, "/admin/assets/images?filter:folder_id=#{c.folder_id}&filter:unused=true")
    assert html =~ "Delete 1 unused"
    refute html =~ "sweep_open"

    view |> element("button[phx-click=delete_unused]") |> render_click()
    assert Repo.get!(Image, c.unused.id).deleted_at
    refute Repo.get!(Image, c.used.id).deleted_at
  end
end
