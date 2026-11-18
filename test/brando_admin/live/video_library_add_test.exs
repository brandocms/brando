defmodule BrandoAdmin.VideoLibraryAddTest do
  @moduledoc """
  The Videos library's "Add from URL" and "Add from <provider>", beside its
  Upload button: a video added either way goes into the folder in view, and
  at the root into the default video config's folder, which the root is.
  The lookups are stubbed: the oEmbed endpoint and Vimeo's API.
  """
  use Brando.LiveCase

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Repo
  alias Brando.Videos.Uploaders.Vimeo
  alias Brando.Videos.Video
  alias BrandoAdmin.Images.FolderBrowser

  @add_url "button[phx-click=open_url_add]"
  @add_vimeo ~s(button[phx-click="open_library"][phx-value-strategy="vimeo"])
  @url_modal "#video-add-url"
  @library_modal "#video-add-library"
  @parser "#video-add-url [phx-hook='Brando.VideoURLParser']"

  @url "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  @params %{"width" => 1280, "height" => 720, "source" => "youtube", "remoteId" => "dQw4w9WgXcQ", "url" => @url}

  setup do
    put_test_env(:default_video_upload_strategy, :local)
    put_test_env(Brando.OEmbed, req_options: [plug: {Req.Test, Brando.OEmbed}])
    put_test_env(Vimeo, access_token: "vimeo-token", req_options: [plug: {Req.Test, Vimeo}])
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    Req.Test.stub(Brando.OEmbed, &Req.Test.json(&1, %{"title" => "Never gonna", "description" => "A classic"}))

    Req.Test.stub(Vimeo, fn
      %{request_path: "/me/videos"} = conn ->
        Req.Test.json(conn, %{
          "paging" => %{"next" => nil},
          "data" => [vimeo_video("11", "Harbour at dawn"), vimeo_video("12", "Night ferry")]
        })

      %{request_path: "/videos/" <> id} = conn ->
        Req.Test.json(conn, vimeo_video(id, "Harbour at dawn"))
    end)

    :ok
  end

  defp vimeo_video(id, name) do
    %{
      "uri" => "/videos/#{id}",
      "name" => name,
      "link" => "https://vimeo.com/#{id}",
      "status" => "available",
      "transcode" => %{"status" => "complete"},
      "width" => 1280,
      "height" => 720,
      "duration" => 30,
      "created_time" => "2026-09-01T10:00:00+00:00",
      "files" => [%{"quality" => "hls", "link" => "https://player.vimeo.com/external/#{id}.m3u8?s=x"}]
    }
  end

  defp paste_url(view, params \\ @params) do
    view |> element(@add_url) |> render_click()
    view |> element(@parser) |> render_hook("url", params)
    render_async(view)
  end

  defp open_vimeo(view) do
    view |> element(@add_vimeo) |> render_click()
    render_async(view)
  end

  defp root_ids, do: FolderBrowser.root_folder_ids("videos/default")

  defp attribute(view, selector, name) do
    view |> render() |> Floki.parse_document!() |> Floki.find(selector) |> Floki.attribute(name) |> List.first()
  end

  describe "Add from URL" do
    test "at the root, creates the video with its title in the root's folder", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      assert has_element?(view, @add_url, "Add from URL")

      view |> element(@add_url) |> render_click()
      # The hook pushes to its own element, which no component encloses: the LiveView
      parser_id = attribute(view, @parser, "id")
      assert attribute(view, @parser, "data-target") == "#" <> parser_id

      paste_url(view)

      video = Repo.one!(Video)
      assert %{title: "Never gonna", caption: "A classic", type: :youtube, config_target: "default"} = video
      assert video.remote_id == "dQw4w9WgXcQ"
      assert video.folder_id in root_ids()

      refute has_element?(view, @url_modal)
      assert has_element?(view, ".image-picker-main-actions span", "1 video")
      _ = render(view)
      assert has_element?(view, "#list-row-#{video.id}")
    end

    test "in a subfolder, the video goes into that folder", %{conn: conn} do
      folder_id = FolderBrowser.folder_id_for("videos/default/clips")
      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{folder_id}")

      paste_url(view)

      assert Repo.one!(Video).folder_id == folder_id
    end

    test "a file address takes its title from the file name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")

      paste_url(view, %{
        "width" => 0,
        "height" => 0,
        "source" => "file",
        "remoteId" => "https://cdn.example.com/launch_reel-01.mp4",
        "url" => "https://cdn.example.com/launch_reel-01.mp4"
      })

      assert %{title: "launch reel 01", type: :external_file} = Repo.one!(Video)
    end

    # The hook reads a file's size in the browser before it pushes, for up to
    # ten seconds. A push from a dialog closed meanwhile finds no element to
    # go to: each opening has its own.
    test "each opening of the dialog has its own URL input", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      view |> element(@add_url) |> render_click()
      first = attribute(view, @parser, "data-target")

      view |> element("#{@url_modal} button.modal-close") |> render_click()
      view |> element(@add_url) |> render_click()

      refute attribute(view, @parser, "data-target") == first
      refute has_element?(view, first)
    end

    test "closing the dialog before the answer creates nothing", %{conn: conn} do
      test_pid = self()

      Req.Test.stub(Brando.OEmbed, fn conn ->
        send(test_pid, {:asked, self()})
        receive do: (:answer -> Req.Test.json(conn, %{"title" => "Late"}))
      end)

      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      view |> element(@add_url) |> render_click()
      view |> element(@parser) |> render_hook("url", @params)
      assert_receive {:asked, lookup}

      view |> element("#{@url_modal} button.modal-close") |> render_click()
      send(lookup, :answer)
      render_async(view)

      assert Repo.aggregate(Video, :count) == 0
      refute has_element?(view, @url_modal)
    end

    # The hook sends no provider or id for an address the browser can't parse
    test "an address the browser couldn't read is refused, and the page stays up", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      view |> element(@add_url) |> render_click()
      view |> element(@parser) |> render_hook("url", %{"width" => 0, "height" => 0, "url" => "www.youtube.com/watch?v=x"})
      render_async(view)

      assert Process.alive?(view.pid)
      assert has_element?(view, @url_modal)
      refute has_element?(view, "#{@url_modal} .video-picker-analyzing:not(.hidden)")
      assert Repo.aggregate(Video, :count) == 0
    end

    test "is not offered when the default video config takes no URLs", %{conn: conn} do
      put_test_env(Brando.Videos, default_config: %Brando.Type.VideoConfig{allow_external_urls: false})

      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      refute has_element?(view, @add_url)
      refute has_element?(view, @add_vimeo)

      # Nor taken from a forged event
      render_hook(view, "url", @params)
      render_async(view)
      assert Repo.aggregate(Video, :count) == 0
    end
  end

  describe "Add from a provider" do
    test "lists the provider's videos and adds one to the root's folder", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      assert has_element?(view, @add_vimeo, "Add from Vimeo")

      open_vimeo(view)
      assert has_element?(view, "#{@library_modal} [data-remote-id=\"11\"]", "Harbour at dawn")
      assert has_element?(view, "#{@library_modal} [data-remote-id=\"11\"]", "0:30 · 1280 × 720 · 2026-09-01")

      view |> element(~s(#{@library_modal} [data-remote-id="11"] button), "Add") |> render_click()

      video = Brando.Videos.get_video_by_meta("vimeo.video_id", "11")
      assert %{type: :vimeo_account, config_target: "default", meta: %{"imported" => true}} = video
      assert video.folder_id in root_ids()

      # Marked as in the library, with nothing to select it for
      assert has_element?(view, ~s(#{@library_modal} [data-remote-id="11"]), "In library")
      refute has_element?(view, ~s(#{@library_modal} [data-remote-id="11"] button))
      # The dialog stays open for the next one, and the list behind it has the video
      assert has_element?(view, @library_modal)
      assert has_element?(view, ".image-picker-main-actions span", "1 video")
    end

    test "in a subfolder, the video goes into that folder", %{conn: conn} do
      folder_id = FolderBrowser.folder_id_for("videos/default/clips")
      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{folder_id}")

      open_vimeo(view)
      view |> element(~s(#{@library_modal} [data-remote-id="11"] button), "Add") |> render_click()

      assert Brando.Videos.get_video_by_meta("vimeo.video_id", "11").folder_id == folder_id
    end

    test "a video Brando holds already is marked, and adding it again neither copies nor moves it", %{conn: conn} do
      elsewhere = FolderBrowser.folder_id_for("videos/default/archive")

      existing =
        Factory.insert(:video,
          type: :vimeo_account,
          folder_id: elsewhere,
          meta: %{"provider" => "vimeo", "vimeo" => %{"video_id" => "11"}}
        )

      clips = FolderBrowser.folder_id_for("videos/default/clips")
      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{clips}")

      open_vimeo(view)
      assert has_element?(view, ~s(#{@library_modal} [data-remote-id="11"]), "In library")
      refute has_element?(view, ~s(#{@library_modal} [data-remote-id="11"] button))

      render_click(view, "add_from_library", %{"remote-id" => "11"})

      assert Repo.aggregate(Video, :count) == 1
      assert Repo.get!(Video, existing.id).folder_id == elsewhere
    end

    test "a trashed record of the video comes back in the folder in view", %{conn: conn} do
      archive = FolderBrowser.folder_id_for("videos/default/archive")

      trashed =
        Factory.insert(:video,
          type: :vimeo_account,
          folder_id: archive,
          deleted_at: DateTime.utc_now(),
          meta: %{"provider" => "vimeo", "imported" => true, "vimeo" => %{"video_id" => "11"}}
        )

      clips = FolderBrowser.folder_id_for("videos/default/clips")
      {:ok, view, _html} = live(conn, "/admin/assets/videos?filter:folder_id=#{clips}")

      open_vimeo(view)
      view |> element(~s(#{@library_modal} [data-remote-id="11"] button), "Add") |> render_click()

      restored = Repo.get!(Video, trashed.id)
      assert is_nil(restored.deleted_at)
      assert restored.folder_id == clips
      assert has_element?(view, "#list-row-#{trashed.id}")
    end

    test "closing the dialog closes the library", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      open_vimeo(view)

      view |> element("#{@library_modal} button.modal-close") |> render_click()
      refute has_element?(view, @library_modal)
    end

    test "is not offered without provider credentials", %{conn: conn} do
      put_test_env(Vimeo, [])

      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      refute has_element?(view, ~s(button[phx-click="open_library"]))
      assert has_element?(view, @add_url)
    end
  end

  # Each test signs in a member of one group with its `keys`
  describe "with group authorization" do
    setup %{keys: keys} do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()

      scope = Scope.standalone(owner)
      member = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      {:ok, group} = Groups.create(scope, %{name: "Library members"}, ~w(brando.admin.access brando.videos.read) ++ keys)
      {:ok, :ok} = Groups.add_member(scope, group.id, member.id)

      %{conn: log_in_user(Phoenix.ConnTest.build_conn(), member)}
    end

    @tag keys: []
    test "reading alone offers neither, and adds nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      refute has_element?(view, @add_url)
      refute has_element?(view, ~s(button[phx-click="open_library"]))

      render_click(view, "open_url_add", %{})
      render_hook(view, "url", @params)
      render_async(view)
      render_click(view, "open_library", %{"strategy" => "vimeo"})
      render_async(view)
      render_click(view, "add_from_library", %{"remote-id" => "11"})

      assert Repo.aggregate(Video, :count) == 0
    end

    @tag keys: ~w(brando.videos.create)
    test "creating offers both, and adds", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      assert has_element?(view, @add_vimeo)

      paste_url(view)
      assert %{type: :youtube} = Repo.one!(Video)

      open_vimeo(view)
      view |> element(~s(#{@library_modal} [data-remote-id="11"] button), "Add") |> render_click()
      assert Brando.Videos.get_video_by_meta("vimeo.video_id", "11")
    end
  end
end
