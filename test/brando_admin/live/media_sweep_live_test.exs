defmodule BrandoAdmin.MediaSweepLiveTest do
  # "Sort by use" and "Delete unused" in the video and file libraries, the
  # image library's (image_sweep_live_test.exs) on the shared sweep.
  use Brando.LiveCase

  import Ecto.Query

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Block
  alias Brando.Files.File, as: MediaFile
  alias Brando.Media.Folder
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Videos.Video
  alias BrandoAdmin.Images.FolderBrowser

  defp show(assets, title \\ "About us") do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title), language: "en")
    Brando.Content.create_identifier(Page, page)
    source = "Elixir.Brando.Pages.Page.Blocks"
    block = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})

    Enum.each(assets, fn
      %Video{id: id} -> Factory.insert(:ref, block_id: block.id, video_id: id)
      %MediaFile{id: id} -> Factory.insert(:ref, block_id: block.id, file_id: id)
    end)
  end

  defp folder_of(%schema{id: id}), do: Repo.one(from a in schema, where: a.id == ^id, select: a.folder_id)

  defp file(folder_id, name) do
    Repo.insert!(%MediaFile{
      filename: name,
      filesize: 100,
      mime_type: "application/pdf",
      config_target: "default",
      folder_id: folder_id
    })
  end

  describe "videos" do
    setup do
      folder_id = FolderBrowser.folder_id_for("videos/default/sweep")
      thumbnail = Factory.insert(:image, status: :processed)
      used = Factory.insert(:video, folder_id: folder_id, thumbnail_id: thumbnail.id)
      unused = Factory.insert(:video, folder_id: folder_id)
      show([used])
      %{folder_id: folder_id, used: used, unused: unused}
    end

    test "previews the folders with thumbnails, moves the videos and undoes it", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}")

      view |> element("button[phx-click=sweep_open]") |> render_click()
      assert has_element?(view, "#video-sweep .media-sweep-entry", "About us")
      assert has_element?(view, ~s(#video-sweep-form input[name="name[pages/about-us]"]))
      assert has_element?(view, "#video-sweep .media-sweep-thumbs img")

      view |> form("#video-sweep-form") |> render_submit()
      assert has_element?(view, "[data-testid=sweep-result]")
      assert Repo.get!(Folder, folder_of(c.used)).path == "default/sweep/pages/about-us"
      assert folder_of(c.unused) == c.folder_id

      view |> element("button[phx-click=sweep_undo]") |> render_click()
      assert folder_of(c.used) == c.folder_id
      refute Repo.get_by(Folder, scope: "videos", path: "default/sweep/pages/about-us")
      refute has_element?(view, "[data-testid=sweep-result]")
    end

    test "a renamed folder is used, an unchecked entry stays, and Cancel closes", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}")
      view |> element("button[phx-click=sweep_open]") |> render_click()
      view |> element("#video-sweep button[phx-click=sweep_close]") |> render_click()
      refute has_element?(view, "#video-sweep")

      view |> element("button[phx-click=sweep_open]") |> render_click()
      view |> form("#video-sweep-form", %{"include" => %{"pages/about-us" => "false"}}) |> render_submit()
      assert folder_of(c.used) == c.folder_id
      refute has_element?(view, "[data-testid=sweep-result]")

      view |> element("button[phx-click=sweep_open]") |> render_click()
      view |> form("#video-sweep-form", %{"name" => %{"pages/about-us" => "sider/om-oss"}}) |> render_submit()
      assert Repo.get!(Folder, folder_of(c.used)).path == "default/sweep/sider/om-oss"

      view |> element("button[phx-click=sweep_dismiss]") |> render_click()
      refute has_element?(view, "[data-testid=sweep-result]")
    end

    test "the unused filter offers to delete every unused video in the folder", %{conn: conn} = c do
      {:ok, _view, html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}")
      refute html =~ "delete_unused"

      {:ok, view, html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}&filter:unused=true")
      assert html =~ "Delete 1 unused"
      assert has_element?(view, "button[phx-click=delete_unused][data-confirm-destructive][data-confirm]")
      refute html =~ "sweep_open"

      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)
      assert Repo.get!(Video, c.unused.id).deleted_at
      refute Repo.get!(Video, c.used.id).deleted_at
      refute has_element?(view, "button[phx-click=delete_unused]")
    end

    test "Delete unused deletes what the confirmation offered, not what arrived since", %{conn: conn} = c do
      {:ok, view, html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}&filter:unused=true")
      assert html =~ "Delete 1 unused"

      # Another editor adds a video, and a page starts using the confirmed one.
      arrived = Factory.insert(:video, folder_id: c.folder_id)
      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)

      assert Repo.get!(Video, c.unused.id).deleted_at
      refute Repo.get!(Video, arrived.id).deleted_at
      # The list is fresh again: the new one is offered now.
      assert render(view) =~ "Delete 1 unused"

      show([arrived], "Contact")
      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)
      refute Repo.get!(Video, arrived.id).deleted_at
    end

    test "Delete unused deletes exactly what the filtered list shows", %{conn: conn} = c do
      named = Factory.insert(:video, folder_id: c.folder_id, title: "Launch teaser")
      nested = Factory.insert(:video, folder_id: FolderBrowser.folder_id_for("videos/default/sweep/older"))

      {:ok, view, html} =
        live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}&filter:unused=true&filter:path=Launch")

      assert html =~ "Delete 1 unused"
      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)
      assert Repo.get!(Video, named.id).deleted_at
      refute Repo.get!(Video, c.unused.id).deleted_at

      # All folders: the subfolder's too, not only the root's.
      {:ok, view, html} = live(conn, "/admin/assets/videos?filter:folder_id=all&filter:unused=true")
      assert html =~ "Delete all 2 unused"
      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)
      assert Repo.get!(Video, c.unused.id).deleted_at
      assert Repo.get!(Video, nested.id).deleted_at
      refute Repo.get!(Video, c.used.id).deleted_at
    end

    test "a video a trashed page uses is not offered for deletion", %{conn: conn} = c do
      page = Repo.one!(from p in Page, where: p.uri == "about-us")
      Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [deleted_at: DateTime.utc_now()])

      {:ok, _view, html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}&filter:unused=true")
      assert html =~ "Delete 1 unused"
      refute html =~ "list-row-#{c.used.id}"
    end

    test "the root offers no sort", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/assets/videos")
      refute html =~ "sweep_open"
    end
  end

  describe "files" do
    setup do
      folder_id = FolderBrowser.folder_id_for("files/default/sweep")
      used = file(folder_id, "price-list.xlsx")
      unused = file(folder_id, "old-terms.pdf")
      show([used])
      %{folder_id: folder_id, used: used, unused: unused}
    end

    test "previews the folders with type icons, moves the files and undoes it", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/assets/files?filter:folder_id=#{c.folder_id}")

      view |> element("button[phx-click=sweep_open]") |> render_click()
      assert has_element?(view, "#file-sweep .media-sweep-entry", "About us")
      assert has_element?(view, "#file-sweep .media-sweep-tile[title='price-list.xlsx'] .lucide-file-spreadsheet")

      view |> form("#file-sweep-form") |> render_submit()
      assert Repo.get!(Folder, folder_of(c.used)).path == "default/sweep/pages/about-us"
      assert folder_of(c.unused) == c.folder_id

      view |> element("button[phx-click=sweep_undo]") |> render_click()
      assert folder_of(c.used) == c.folder_id
      refute Repo.get_by(Folder, scope: "files", path: "default/sweep/pages")
    end

    test "the unused filter offers to delete every unused file in the folder", %{conn: conn} = c do
      {:ok, view, html} = live(conn, "/admin/assets/files?filter:folder_id=#{c.folder_id}&filter:unused=true")
      assert html =~ "Delete 1 unused"

      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)
      assert Repo.get!(MediaFile, c.unused.id).deleted_at
      refute Repo.get!(MediaFile, c.used.id).deleted_at
    end

    test "a file in a table block's row is used, and Delete unused keeps it", %{conn: conn} = c do
      download = file(c.folder_id, "downloads.pdf")
      source = "Elixir.Brando.Pages.Page.Blocks"
      block = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
      page = Repo.one!(from p in Page, where: p.uri == "about-us")
      Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 1})
      row = Repo.insert!(%Brando.Content.TableRow{block_id: block.id, sequence: 0})

      Repo.insert!(%Brando.Content.Var{
        type: :file,
        key: "download",
        label: %{"en" => "Download"},
        table_row_id: row.id,
        file_id: download.id
      })

      {:ok, view, html} = live(conn, "/admin/assets/files?filter:folder_id=#{c.folder_id}&filter:unused=true")
      assert html =~ "Delete 1 unused"
      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)
      refute Repo.get!(MediaFile, download.id).deleted_at
      assert Repo.get!(MediaFile, c.unused.id).deleted_at
    end
  end

  describe "with group authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()

      folder_id = FolderBrowser.folder_id_for("videos/default/sweep")
      used = Factory.insert(:video, folder_id: folder_id)
      unused = Factory.insert(:video, folder_id: folder_id)
      show([used])

      %{scope: Scope.standalone(owner), folder_id: folder_id, used: used, unused: unused}
    end

    defp member(c, keys) do
      user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      log_in_user(Phoenix.ConnTest.build_conn(), user)
    end

    test "reading alone offers neither, and asking anyway changes nothing", c do
      conn = member(c, ~w(brando.admin.access brando.videos.read))

      {:ok, view, html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}")
      refute html =~ "sweep_open"

      render_click(view, "sweep_open", %{})
      render_submit(view, "sweep_apply", %{})
      assert folder_of(c.used) == c.folder_id

      {:ok, view, html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}&filter:unused=true")
      refute html =~ "delete_unused"

      render_click(view, "delete_unused", %{})
      render_async(view)
      refute Repo.get!(Video, c.unused.id).deleted_at
    end

    test "updating sorts, deleting deletes", c do
      conn = member(c, ~w(brando.admin.access brando.videos.read brando.videos.update brando.videos.delete))

      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}")
      view |> element("button[phx-click=sweep_open]") |> render_click()
      view |> form("#video-sweep-form") |> render_submit()
      refute folder_of(c.used) == c.folder_id

      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{c.folder_id}&filter:unused=true")
      view |> element("button[phx-click=delete_unused]") |> render_click()
      render_async(view)
      assert Repo.get!(Video, c.unused.id).deleted_at
    end
  end
end
