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
