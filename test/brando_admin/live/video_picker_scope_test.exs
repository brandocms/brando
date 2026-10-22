defmodule BrandoAdmin.VideoPickerScopeTest do
  @moduledoc """
  A video picker opened for one field lists the videos added for it, and
  offers the whole library besides, the way the image picker does. A field
  with its own video cfg otherwise saw none of the site's videos: they were
  all added under `"default"`, filed in the library's `default` folder.

  A video picked from the library is linked as it is. New videos still take
  the field's config, whichever scope is on screen.
  """
  use Brando.LiveCase

  alias Brando.Videos.Video
  alias BrandoAdmin.Components.VideoPicker
  alias BrandoAdmin.Images.FolderBrowser

  # A field with its own cfg: `upload_path: "videos/posts"`
  @field_target {"video", Brando.JSONLDTest.Post, :cover_video}
  @field_target_string "video:Brando.JSONLDTest.Post:cover_video"

  # Stands in for the video field that opened the picker: records the video
  # picked for it.
  defmodule Field do
    @moduledoc false
    use Phoenix.LiveComponent

    def render(assigns), do: ~H"<div id={@id}></div>"

    def update(assigns, socket), do: {:ok, assign(socket, assigns)}

    def handle_event("select_video", %{"id" => id}, socket) do
      send(socket.assigns.test_pid, {:video_selected, id})
      {:noreply, socket}
    end
  end

  defmodule Host do
    @moduledoc false
    use Phoenix.LiveView

    def mount(_params, %{"test_pid" => test_pid, "user" => user}, socket) do
      {:ok, assign(socket, test_pid: test_pid, current_user: user)}
    end

    def render(assigns) do
      ~H"""
      <.live_component module={Field} id="video-field" test_pid={@test_pid} />
      <.live_component module={VideoPicker} id="video-picker" current_user={@current_user} />
      """
    end
  end

  setup %{current_user: user} do
    default_folder = FolderBrowser.folder_id_for("default", "videos")

    {:ok,
     filed: Factory.insert(:video, title: "Filed in default", config_target: "default", folder_id: default_folder),
     loose: Factory.insert(:video, title: "Loose default", config_target: "default"),
     other:
       Factory.insert(:video, title: "Another field's", config_target: "video:Brando.JSONLDTest.QuietPost:cover_video"),
     own: Factory.insert(:video, title: "This field's own", config_target: @field_target_string),
     user: user}
  end

  test "opens on the field's own videos and offers the whole library", %{conn: conn, user: user} do
    view = open_picker(conn, user, @field_target)

    assert listed(view) == ["This field's own"]
    assert has_element?(view, "#video-picker .image-picker-scope button[aria-pressed=true]", "Added for this field")
    assert has_element?(view, "#video-picker h3", "videos/posts")
  end

  test "the whole library lists every target, with its folders", %{conn: conn, user: user} do
    view = open_picker(conn, user, @field_target)

    view |> element("#video-picker .image-picker-scope button", "Whole library") |> render_click()

    assert has_element?(view, "#video-picker h3", "videos")
    assert has_element?(view, ~s(#video-picker .folder-row[data-drop-folder="default"]))
    # Videos with no folder, of any target, are at the library's root
    assert Enum.sort(listed(view)) == ["Another field's", "Loose default", "This field's own"]

    view |> element(~s(#video-picker .folder-row[data-drop-folder="default"])) |> render_click()

    assert listed(view) == ["Filed in default"]
    assert has_element?(view, "#video-picker h3", "videos/default")
  end

  test "a video picked from the library is linked as it is", %{conn: conn, user: user, filed: filed} do
    view = open_picker(conn, user, @field_target)
    view |> element("#video-picker .image-picker-scope button", "Whole library") |> render_click()
    view |> element(~s(#video-picker .folder-row[data-drop-folder="default"])) |> render_click()

    view |> element(~s(#video-picker .video-picker__video[data-id="#{filed.id}"])) |> render_click()

    filed_id = to_string(filed.id)
    assert_received {:video_selected, ^filed_id}
    assert Brando.Repo.aggregate(Video, :count) == 4
    assert Brando.Repo.reload!(filed).config_target == "default"
  end

  test "Root at the field's own root leads into the library", %{conn: conn, user: user} do
    view = open_picker(conn, user, @field_target)

    view |> with_target(cid_of(view, "#video-picker")) |> render_click("picker_go_root", %{})

    assert has_element?(view, "#video-picker .image-picker-scope button[aria-pressed=true]", "Whole library")
  end

  test "an upload from the whole library still takes the field's target and upload path",
       %{conn: conn, user: user} do
    view = open_picker(conn, user, @field_target, upload_strategy: :local)
    view |> element("#video-picker .image-picker-scope button", "Whole library") |> render_click()

    # What the upload manager is handed by the picker's trigger
    [target] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#video-uploader-video-picker")
      |> LazyHTML.attribute("data-config-target")

    assert target == @field_target_string

    {cfg, ^target} = Brando.Uploads.resolve_video_config(target)
    tmp = Path.join(System.tmp_dir!(), "picker-upload-#{System.unique_integer([:positive])}.mp4")
    File.write!(tmp, :crypto.strong_rand_bytes(1024))
    on_exit(fn -> File.rm(tmp) end)

    entry = %{client_name: "clip.mp4", client_type: "video/mp4", client_size: 1024}

    assert {:ok, %Video{} = video} =
             Brando.Uploads.Store.handle_upload(%{path: tmp, config_target: target}, entry, cfg, user)

    video = Brando.Repo.preload(video, :file)
    assert video.config_target == @field_target_string
    assert Brando.Utils.media_url(video.file) =~ "/videos/posts/clip.mp4"
  end

  test "a gallery's pick (several videos) is not offered the library", %{conn: conn, user: user} do
    view = open_picker(conn, user, @field_target, multi: true)

    refute has_element?(view, "#video-picker .image-picker-scope")
    assert listed(view) == ["This field's own"]
  end

  test "`config_target: :all` lists every video and adds none", %{conn: conn, user: user} do
    view = open_picker(conn, user, :all, multi: true)

    refute has_element?(view, "#video-picker .image-picker-scope")
    refute has_element?(view, "#video-picker button", "Add from URL")
    refute has_element?(view, "#video-picker button", "Upload file")
    assert length(listed(view)) == 4
  end

  defp open_picker(conn, user, config_target, opts \\ []) do
    {:ok, view, _html} = live_isolated(conn, Host, session: %{"test_pid" => self(), "user" => user})

    Phoenix.LiveView.send_update(
      view.pid,
      VideoPicker,
      Keyword.merge(
        [
          id: "video-picker",
          config_target: config_target,
          event_target: %Phoenix.LiveComponent.CID{cid: cid_of(view, "#video-field")},
          multi: false,
          selected_videos: []
        ],
        opts
      )
    )

    view
  end

  # The titles of the videos on screen
  defp listed(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#video-picker .video-picker__title")
    |> Enum.map(&LazyHTML.text/1)
  end
end
