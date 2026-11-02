defmodule BrandoAdmin.VideoPickerPreviewTest do
  @moduledoc """
  A stored address can hold anything, and the preview's iframe would run it. So
  the preview reads the row on the server and embeds only a URL it builds on the
  provider's host, or plays a file in a `<video>`; nothing the browser sends
  picks what plays.
  """
  use Brando.LiveCase

  alias BrandoAdmin.Components.VideoPicker

  @field_target {"video", Brando.JSONLDTest.Post, :cover_video}
  @field_target_string "video:Brando.JSONLDTest.Post:cover_video"

  # Inert: a script-scheme address that would only set the page title
  @script_scheme "javascript:document.title='f05'"
  @script_scheme_watch "javascript:document.title='f05'//watch?v=dQw4w9WgXcQ"
  @script_scheme_short "javascript:document.title='f05'//youtu.be/dQw4w9WgXcQ"

  defmodule Field do
    @moduledoc false
    use Phoenix.LiveComponent

    def render(assigns), do: ~H"<div id={@id}></div>"
    def update(assigns, socket), do: {:ok, assign(socket, assigns)}
  end

  defmodule Host do
    @moduledoc false
    use Phoenix.LiveView

    def mount(_params, %{"user" => user}, socket), do: {:ok, assign(socket, current_user: user)}

    def render(assigns) do
      ~H"""
      <.live_component module={Field} id="video-field" />
      <.live_component module={VideoPicker} id="video-picker" current_user={@current_user} />
      """
    end
  end

  describe "a stored address that is not a provider's" do
    for {name, address} <- [
          fallback: @script_scheme,
          watch: @script_scheme_watch,
          short: @script_scheme_short
        ] do
      test "a YouTube row without an id plays nothing (#{name})", %{conn: conn, current_user: user} do
        video = stored(type: :youtube, source_url: unquote(address), remote_id: nil)

        html = play(conn, user, video)

        assert iframe_sources(html) == []
        refute html =~ "javascript:"
      end

      test "a YouTube row with an id embeds the id, not the address (#{name})", %{conn: conn, current_user: user} do
        video = stored(type: :youtube, source_url: unquote(address), remote_id: "dQw4w9WgXcQ")

        assert [src] = conn |> play(user, video) |> iframe_sources()
        assert src == "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"
      end
    end

    test "the address in the event is ignored", %{conn: conn, current_user: user} do
      video = stored(type: :youtube, source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", remote_id: nil)

      html =
        conn
        |> open_picker(user)
        |> element(preview(video))
        |> render_click(%{"source-url" => @script_scheme})

      assert iframe_sources(html) == ["https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"]
    end

    test "the address is not handed to the browser in the listing", %{conn: conn, current_user: user} do
      stored(type: :youtube, source_url: @script_scheme, remote_id: nil)

      refute conn |> open_picker(user) |> render() =~ "phx-value-source-url"
    end

    test "a non-YouTube page typed as YouTube plays nothing", %{conn: conn, current_user: user} do
      video = stored(type: :youtube, source_url: "https://example.com/watch?v=dQw4w9WgXcQ", remote_id: nil)

      assert conn |> play(user, video) |> iframe_sources() == []
    end

    test "a YouTube playlist embed plays nothing", %{conn: conn, current_user: user} do
      video = stored(type: :youtube, source_url: "https://www.youtube.com/embed/videoseries?list=PL1", remote_id: nil)

      assert conn |> play(user, video) |> iframe_sources() == []
    end

    test "a Vimeo row with a script-scheme address plays nothing", %{conn: conn, current_user: user} do
      video = stored(type: :vimeo, source_url: @script_scheme, remote_id: nil)

      html = play(conn, user, video)

      assert iframe_sources(html) == []
      refute html =~ "javascript:"
    end
  end

  describe "previewing" do
    test "a YouTube row with an id", %{conn: conn, current_user: user} do
      video = stored(type: :youtube, source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", remote_id: "dQw4w9WgXcQ")

      assert conn |> play(user, video) |> iframe_sources() == ["https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"]
    end

    test "a YouTube row with only an id", %{conn: conn, current_user: user} do
      video = stored(type: :youtube, source_url: nil, remote_id: "dQw4w9WgXcQ")

      assert conn |> play(user, video) |> iframe_sources() == ["https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"]
    end

    for address <- [
          "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10",
          "https://youtu.be/dQw4w9WgXcQ?si=abc",
          "https://www.youtube.com/embed/dQw4w9WgXcQ"
        ] do
      test "a YouTube row with only the address #{address}", %{conn: conn, current_user: user} do
        video = stored(type: :youtube, source_url: unquote(address), remote_id: nil)

        assert conn |> play(user, video) |> iframe_sources() == ["https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"]
      end
    end

    test "a Vimeo row keeps an unlisted video's hash", %{conn: conn, current_user: user} do
      video = stored(type: :vimeo, source_url: "https://vimeo.com/76979871/abcdef1234", remote_id: "76979871")

      assert conn |> play(user, video) |> iframe_sources() ==
               ["https://player.vimeo.com/video/76979871?h=abcdef1234&autoplay=1"]
    end

    test "a Vimeo row with only an address", %{conn: conn, current_user: user} do
      video = stored(type: :vimeo, source_url: "https://vimeo.com/76979871", remote_id: nil)

      assert conn |> play(user, video) |> iframe_sources() == ["https://player.vimeo.com/video/76979871?autoplay=1"]
    end

    test "a Vimeo row with only an id", %{conn: conn, current_user: user} do
      video = stored(type: :vimeo, source_url: nil, remote_id: "76979871")

      assert conn |> play(user, video) |> iframe_sources() == ["https://player.vimeo.com/video/76979871?autoplay=1"]
    end

    test "a Vimeo account row takes an unlisted video's hash from its meta", %{conn: conn, current_user: user} do
      video =
        stored(
          type: :vimeo_account,
          source_url: "https://vimeo.com/76979871",
          remote_id: "76979871",
          meta: %{"vimeo" => %{"video_id" => "76979871", "hash" => "abcdef1234"}}
        )

      assert conn |> play(user, video) |> iframe_sources() ==
               ["https://player.vimeo.com/video/76979871?h=abcdef1234&autoplay=1"]
    end

    test "a Vimeo account row without Vimeo meta reads its address", %{conn: conn, current_user: user} do
      video = stored(type: :vimeo_account, source_url: "https://vimeo.com/76979871/abcdef1234", remote_id: nil, meta: %{})

      assert conn |> play(user, video) |> iframe_sources() ==
               ["https://player.vimeo.com/video/76979871?h=abcdef1234&autoplay=1"]
    end

    test "a Vimeo account row with a file link plays the file", %{conn: conn, current_user: user} do
      video =
        stored(
          type: :vimeo_account,
          status: :ready,
          source_url: "https://vimeo.com/76979871",
          remote_id: "76979871",
          meta: %{"vimeo" => %{"video_id" => "76979871", "hls_url" => "https://player.vimeo.com/play/1.m3u8"}}
        )

      html = play(conn, user, video)

      assert iframe_sources(html) == []
      assert html =~ ~s(<source src="https://player.vimeo.com/play/1.m3u8")
    end

    test "a linked file", %{conn: conn, current_user: user} do
      video = stored(type: :external_file, source_url: "https://example.com/clip.mp4", remote_id: nil)

      html = play(conn, user, video)

      assert iframe_sources(html) == []
      assert html =~ ~s(<source src="https://example.com/clip.mp4")
    end

    test "an uploaded file", %{conn: conn, current_user: user} do
      file = Brando.Repo.insert!(%Brando.Files.File{filename: "clip.mp4", filesize: 1, config_target: "default"})

      video =
        Factory.insert(:upload_video,
          title: "Clip",
          remote_id: nil,
          file_id: file.id,
          config_target: @field_target_string
        )

      html = play(conn, user, video)

      assert iframe_sources(html) == []
      assert html =~ ~r/<source src="[^"]*clip\.mp4"/
    end
  end

  defp stored(attrs) do
    Factory.insert(:video, [title: "Clip", config_target: @field_target_string] ++ attrs)
  end

  defp play(conn, user, video) do
    conn
    |> open_picker(user)
    |> element(preview(video))
    |> render_click()
  end

  defp preview(video), do: ~s(#video-picker .video-preview[phx-value-video-id="#{video.id}"])

  defp open_picker(conn, user) do
    {:ok, view, _html} = live_isolated(conn, Host, session: %{"user" => user})

    Phoenix.LiveView.send_update(view.pid, VideoPicker,
      id: "video-picker",
      config_target: @field_target,
      event_target: %Phoenix.LiveComponent.CID{cid: cid_of(view, "#video-field")},
      multi: false,
      selected_videos: []
    )

    render(view)
    view
  end

  defp iframe_sources(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#video-player-modal iframe")
    |> LazyHTML.attribute("src")
  end
end
