defmodule BrandoAdmin.VideoLibraryUploadTest do
  @moduledoc """
  The Videos library's header: an Upload button into the folder in view, as
  the Images library has, and "Sort by use" wherever loose videos lie. The
  library's root is the default video config's upload folder, so that
  includes the root.
  """
  # Grouped, one at a time: it takes the authorization lock (Brando.Authorization.Groups.lock!/0),
  # which a test's sandbox transaction holds until the test ends
  use Brando.LiveCase, async: true, group: :shared_locks

  import Ecto.Query

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Block
  alias Brando.Media.Folder
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Video
  alias BrandoAdmin.Images.FolderBrowser

  @upload "#library-video-upload"
  @provider_upload "#library-video-provider-upload"
  @sort "button[phx-click=sweep_open]"
  @guid "6f2c1a3e-1111-2222-3333-444455556666"

  defp show(videos, title \\ "About us") do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title), language: "en")
    Brando.Content.create_identifier(Page, page)

    block =
      Repo.insert!(%Block{type: :module, source: "Elixir.Brando.Pages.Page.Blocks", uid: Brando.Utils.generate_uid()})

    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    Enum.each(videos, &Factory.insert(:ref, block_id: block.id, video_id: &1.id))
  end

  defp folder_of(%Video{id: id}), do: Repo.one(from v in Video, where: v.id == ^id, select: v.folder_id)

  defp attribute(view, selector, name) do
    view |> render() |> Floki.parse_document!() |> Floki.find(selector) |> Floki.attribute(name) |> List.first()
  end

  defp bunny do
    put_test_env(:default_video_upload_strategy, :bunny)

    put_test_env(Bunny,
      api_key: "key",
      library_id: "77",
      cdn_hostname: "vz-1.b-cdn.net",
      webhook_secret: "whsec",
      req_options: [plug: {Req.Test, Bunny}]
    )

    Req.Test.stub(Bunny, fn %{method: "POST", request_path: "/library/77/videos"} = conn ->
      Req.Test.json(conn, %{"guid" => @guid, "videoLibraryId" => 77, "title" => "Clip"})
    end)
  end

  defp start_provider_upload(view, request_ref, opening) do
    view
    |> element(@provider_upload)
    |> render_hook("get_video_upload_url", %{
      "request_ref" => request_ref,
      "opening" => opening,
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })

    assert_push_event(view, "video_upload_url_ready", %{
      request_ref: ^request_ref,
      video_id: video_id,
      upload_token: token
    })

    {video_id, token}
  end

  describe "with local uploads" do
    setup do
      put_test_env(:default_video_upload_strategy, :local)
      :ok
    end

    test "the root uploads into the default video folder and sorts its loose videos", %{conn: conn} do
      Factory.insert(:video)
      {:ok, view, _html} = live(conn, "/admin/assets/videos")

      assert has_element?(
               view,
               ~s(#{@upload}[phx-hook="Brando.UploadTrigger"][data-kind="asset_library"][data-asset-type="video"][data-config-target="default"])
             )

      assert has_element?(view, "#{@upload} button.upload-trigger", "Upload")
      refute has_element?(view, @provider_upload)
      # The root's own folder: what the library lists at the root
      root_id = String.to_integer(attribute(view, @upload, "data-folder-id"))
      assert root_id in FolderBrowser.root_folder_ids("videos/default")
      assert has_element?(view, @sort)
    end

    test "a subfolder uploads into itself and sorts its videos", %{conn: conn} do
      folder_id = FolderBrowser.folder_id_for("videos/default/clips")
      Factory.insert(:video, folder_id: folder_id)

      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{folder_id}")

      assert attribute(view, @upload, "data-folder-id") == to_string(folder_id)
      assert attribute(view, @upload, "data-folder") == "videos/default/clips"
      assert has_element?(view, @sort)
    end

    test "an empty folder offers the upload, and no sort", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      assert has_element?(view, @upload)
      refute has_element?(view, @sort)
    end

    test "a video the upload manager delivers shows in the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      topic = attribute(view, @upload, "data-deliver-topic")
      assert "form:" <> _ = topic

      video = Factory.insert(:video, title: "Fresh upload")
      Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {:asset_ready, %{"kind" => "asset_library"}, video})

      assert has_element?(view, ".image-picker-main-actions span", "1 video")
      # The listing refreshes on the update the view sends it
      _ = render(view)
      assert has_element?(view, "#list-row-#{video.id}")
    end
  end

  describe "without an upload available" do
    test "no upload is offered, and the root still sorts", %{conn: conn} do
      put_test_env(:default_video_upload_strategy, :none)
      Factory.insert(:video)

      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      refute has_element?(view, @upload)
      refute has_element?(view, @provider_upload)
      assert has_element?(view, @sort)
    end

    test "a provider without credentials offers no upload", %{conn: conn} do
      put_test_env(:default_video_upload_strategy, :bunny)
      put_test_env(Bunny, api_key: nil, library_id: nil)

      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      refute has_element?(view, @upload)
      refute has_element?(view, @provider_upload)
    end
  end

  describe "with a provider" do
    setup do
      bunny()
      :ok
    end

    test "the provider's hook takes the upload, into the folder in view", %{conn: conn} do
      folder_id = FolderBrowser.folder_id_for("videos/default/clips")
      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{folder_id}")

      assert has_element?(view, ~s(#{@provider_upload}[phx-hook="Brando.BunnyUploader"]))
      refute has_element?(view, @upload)

      # The hook sends the folder it had when the file was queued (`data-ref`)
      opening = attribute(view, @provider_upload, "data-ref")
      assert opening == to_string(folder_id)
      {video_id, token} = start_provider_upload(view, "lib-1", opening)

      video = Repo.get!(Video, video_id)
      assert video.folder_id == folder_id
      assert video.config_target == "default"

      view
      |> element(@provider_upload)
      |> render_hook("video_upload_complete", %{"request_ref" => "lib-1", "upload_token" => token})

      _ = render(view)
      assert has_element?(view, "#list-row-#{video_id}")
    end

    test "at the root the video goes into the root and lists there", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      opening = attribute(view, @provider_upload, "data-ref")
      assert String.to_integer(opening) in FolderBrowser.root_folder_ids("videos/default")

      {video_id, token} = start_provider_upload(view, "lib-root", opening)
      assert to_string(Repo.get!(Video, video_id).folder_id) == opening

      view
      |> element(@provider_upload)
      |> render_hook("video_upload_complete", %{"request_ref" => "lib-root", "upload_token" => token})

      _ = render(view)
      assert has_element?(view, "#list-row-#{video_id}")
      assert has_element?(view, ".image-picker-main-actions span", "1 video")
    end

    test "a folder outside the library is not taken from the browser", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")

      for folder_id <- [
            FolderBrowser.folder_id_for("files/default/clips"),
            Brando.Media.Folders.hidden_folder_id("uploads"),
            "nonsense"
          ] do
        {video_id, _token} = start_provider_upload(view, "lib-#{folder_id}", to_string(folder_id))
        assert Repo.get!(Video, video_id).folder_id == nil
      end
    end

    test "a completion without the token signed for it is ignored", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")

      view
      |> element(@provider_upload)
      |> render_hook("video_upload_complete", %{"request_ref" => "lib-1", "upload_token" => "forged"})

      assert has_element?(view, @provider_upload)
    end
  end

  # The root's loose videos: those with no folder, and those in the root's
  # own folder record. Images keep their root without a sort.
  test "Sort by use at the root sorts the root's loose videos", %{conn: conn} do
    root = FolderBrowser.folder_id_for("videos/default")
    clips = FolderBrowser.folder_id_for("videos/default/clips")
    loose = Factory.insert(:video)
    in_root = Factory.insert(:video, folder_id: root)
    filed = Factory.insert(:video, folder_id: clips)
    unused = Factory.insert(:video)
    show([loose, in_root, filed])

    {:ok, view, _html} = live(conn, "/admin/assets/videos")
    view |> element(@sort) |> render_click()
    assert has_element?(view, "#video-sweep .media-sweep-entry", "About us")

    view |> form("#video-sweep-form") |> render_submit()
    assert Repo.get!(Folder, folder_of(loose)).path == "default/pages/about-us"
    assert folder_of(in_root) == folder_of(loose)
    assert folder_of(filed) == clips
    assert folder_of(unused) == nil
    # Only the unused one is left at the root
    assert has_element?(view, ".image-picker-main-actions span", "1 video")

    view |> element("button[phx-click=sweep_undo]") |> render_click()
    assert folder_of(loose) == nil
    assert folder_of(in_root) == nil
  end

  test "the image library's root still offers no sort", %{conn: conn} do
    Factory.insert(:image, folder_id: nil, path: "images/loose.jpg")
    {:ok, _view, html} = live(conn, "/admin/assets/images?filter:folder_id=root")
    refute html =~ "sweep_open"
  end

  # Each test signs in a member of one group with its `keys`
  describe "with group authorization" do
    setup %{keys: keys} do
      put_test_env(:default_video_upload_strategy, :local)
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()
      Factory.insert(:video)

      scope = Scope.standalone(owner)
      member = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      {:ok, group} = Groups.create(scope, %{name: "Library members"}, ~w(brando.admin.access brando.videos.read) ++ keys)
      {:ok, :ok} = Groups.add_member(scope, group.id, member.id)

      %{conn: log_in_user(Phoenix.ConnTest.build_conn(), member)}
    end

    @tag keys: []
    test "reading alone offers neither", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      refute has_element?(view, @upload)
      refute has_element?(view, @sort)
    end

    @tag keys: ~w(brando.videos.create)
    test "creating offers the upload", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      assert has_element?(view, @upload)
      refute has_element?(view, @sort)
    end

    @tag keys: ~w(brando.videos.update)
    test "updating offers the sort", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      refute has_element?(view, @upload)
      assert has_element?(view, @sort)
    end

    @tag keys: ~w(brando.videos.create)
    test "a provider upload with the right to create makes the video", %{conn: conn} do
      bunny()
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      {video_id, _token} = start_provider_upload(view, "lib-1", attribute(view, @provider_upload, "data-ref"))
      assert Repo.get!(Video, video_id).type == :bunny
    end

    @tag keys: []
    test "a provider upload asked for without the right to create makes no video", %{conn: conn} do
      bunny()
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      before = Repo.aggregate(Video, :count)

      render_hook(view, "get_video_upload_url", %{
        "request_ref" => "lib-1",
        "filename" => "clip.mp4",
        "size" => 1_000,
        "mime_type" => "video/mp4"
      })

      assert Repo.aggregate(Video, :count) == before
    end
  end
end
