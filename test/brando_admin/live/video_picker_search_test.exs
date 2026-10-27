defmodule BrandoAdmin.VideoPickerSearchTest do
  @moduledoc """
  The video picker's search narrows the videos listed in its folder by title,
  source URL, provider id or an uploaded file's name, as the image picker's
  does. It is not the search of a provider's library, which has its own.
  """
  use Brando.LiveCase

  alias BrandoAdmin.Components.VideoPicker

  @field_target {"video", Brando.JSONLDTest.Post, :cover_video}
  @field_target_string "video:Brando.JSONLDTest.Post:cover_video"

  # Stands in for the video field that opened the picker
  defmodule Field do
    @moduledoc false
    use Phoenix.LiveComponent

    def render(assigns), do: ~H"<div id={@id}></div>"

    # A video handed to the field
    def update(%{event: "select_video"}, socket), do: {:ok, socket}
    def update(assigns, socket), do: {:ok, assign(socket, assigns)}
  end

  defmodule Host do
    @moduledoc false
    use Phoenix.LiveView

    def mount(_params, %{"user" => user}, socket) do
      {:ok, assign(socket, current_user: user)}
    end

    def render(assigns) do
      ~H"""
      <.live_component module={Field} id="video-field" />
      <.live_component module={VideoPicker} id="video-picker" current_user={@current_user} />
      """
    end
  end

  setup %{current_user: user} do
    file = Brando.Repo.insert!(%Brando.Files.File{filename: "harbour-raw.mp4", filesize: 1, config_target: "default"})

    Factory.insert(:video, title: "Harbour at dawn", config_target: @field_target_string)

    Factory.insert(:video,
      title: "Interview",
      source_url: "https://vimeo.com/76979871",
      remote_id: "76979871",
      type: :vimeo,
      config_target: @field_target_string
    )

    Factory.insert(:upload_video,
      title: "Opening titles",
      remote_id: nil,
      file_id: file.id,
      config_target: @field_target_string
    )

    {:ok, user: user}
  end

  test "lists only the videos matching the search", %{conn: conn, user: user} do
    view = open_picker(conn, user)
    assert Enum.sort(listed(view)) == ["Harbour at dawn", "Interview", "Opening titles"]

    assert search(view, "HARBOUR at") == ["Harbour at dawn"]
    assert has_element?(view, "#video-picker .image-picker-main-actions span", "1 video")
    # The source URL and the provider's id
    assert search(view, "vimeo.com") == ["Interview"]
    assert search(view, "76979871") == ["Interview"]
    # The uploaded file's name
    assert search(view, "raw.mp4") == ["Opening titles"]
    assert search(view, "  ") |> Enum.sort() == ["Harbour at dawn", "Interview", "Opening titles"]
  end

  test "says when nothing matches, and clears the search", %{conn: conn, user: user} do
    view = open_picker(conn, user)

    assert search(view, "nothing like it") == []
    assert has_element?(view, "#video-picker .image-picker-empty h4", "No videos match “nothing like it”.")
    refute has_element?(view, "#video-picker .image-picker-empty h4", "No videos in this folder")

    view |> element("#video-picker .image-picker-empty button", "Clear search") |> render_click()

    assert length(listed(view)) == 3
    refute has_element?(view, "#video-picker .image-picker-empty")
  end

  test "a new opening starts without the last search", %{conn: conn, user: user} do
    view = open_picker(conn, user)
    assert search(view, "dawn") == ["Harbour at dawn"]

    reopen(view)

    assert length(listed(view)) == 3
    assert view |> element("#video-picker-search-video-picker input") |> render() =~ ~s(value="")
  end

  # An uploaded video's remote id is its stored path: the folder in it
  # would match every upload, so only its file name counts.
  test "an uploaded video's folder path doesn't match", %{conn: conn, user: user} do
    Factory.insert(:upload_video,
      title: "Stored upload",
      remote_id: "videos/posts/stored-upload.mp4",
      config_target: @field_target_string
    )

    view = open_picker(conn, user)
    assert "Stored upload" in listed(view)

    assert search(view, "videos/posts") == []
    assert search(view, "stored-upload") == ["Stored upload"]
  end

  test "a video added here during a search is listed, and the search cleared", %{conn: conn, user: user} do
    # Uploads to the server, through the picker's upload trigger
    put_test_env(:default_video_upload_strategy, :local)
    view = open_picker(conn, user)
    assert search(view, "dawn") == ["Harbour at dawn"]

    video = Factory.insert(:video, title: "Just added", config_target: @field_target_string)
    deliver_upload(view, video, ref: picker_attribute(view, "data-ref"), expected_asset_id: "none")

    assert "Just added" in listed(view)
    assert view |> element("#video-picker-search-video-picker input") |> render() =~ ~s(value="")
  end

  # An upload started in an earlier opening goes to that opening's field;
  # the search on screen is for this one.
  test "an upload for another opening keeps the search", %{conn: conn, user: user} do
    view = open_picker(conn, user)
    assert search(view, "dawn") == ["Harbour at dawn"]

    video = Factory.insert(:video, title: "Just added", config_target: @field_target_string)
    deliver_upload(view, video, ref: "vp-0", expected_asset_id: "none")

    assert listed(view) == ["Harbour at dawn"]
  end

  defp open_picker(conn, user) do
    {:ok, view, _html} = live_isolated(conn, Host, session: %{"user" => user})
    reopen(view)
    view
  end

  defp reopen(view) do
    Phoenix.LiveView.send_update(view.pid, VideoPicker,
      id: "video-picker",
      config_target: @field_target,
      event_target: %Phoenix.LiveComponent.CID{cid: cid_of(view, "#video-field")},
      multi: false,
      selected_videos: []
    )
  end

  # What the upload manager delivers to the picker once a server upload is stored
  defp deliver_upload(view, video, opts) do
    Phoenix.LiveView.send_update(
      view.pid,
      VideoPicker,
      [id: "video-picker", event: "upload_complete", asset: video] ++ opts
    )
  end

  defp picker_attribute(view, attribute) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#video-uploader-video-picker")
    |> LazyHTML.attribute(attribute)
    |> List.first()
  end

  defp search(view, text) do
    view |> form("#video-picker-search-video-picker", %{search: text}) |> render_change()
    listed(view)
  end

  defp listed(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#video-picker .video-picker__title")
    |> Enum.map(&LazyHTML.text/1)
  end
end
