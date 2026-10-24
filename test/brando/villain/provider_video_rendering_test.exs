defmodule Brando.Villain.ProviderVideoRenderingTest do
  # A video block or ref holding a provider's video (Bunny, Mux, Cloudflare, a
  # Vimeo account) renders as `Brando.HTML.video/1` renders the record, with
  # the block's settings. The parser had clauses for YouTube, Vimeo, external
  # files and uploads only, and rendered every provider video as "".
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Content
  alias Brando.Factory
  alias Brando.Utils
  alias Brando.Videos.Video
  alias Brando.Villain.Parser

  @guid "6f2c1a3e-1111-2222-3333-444455556666"

  # A site's parser that overrides `video_file_options/1`
  defmodule SiteParser do
    @moduledoc false
    use Brando.Villain.Parser

    def video_file_options(data), do: Keyword.put(super(data), :progress, true)
  end

  setup do
    put_test_env(Brando.Videos.Uploaders.Bunny, cdn_hostname: "vz-1.b-cdn.net")
    :ok
  end

  defp bunny(attrs \\ %{}) do
    struct(
      %Video{
        type: :bunny,
        status: :ready,
        width: 1080,
        height: 1350,
        meta: %{"bunny" => %{"video_guid" => @guid}}
      },
      attrs
    )
  end

  defp mux(attrs \\ %{}) do
    struct(
      %Video{
        type: :mux,
        status: :ready,
        width: 1920,
        height: 1080,
        meta: %{"mux" => %{"playback_id" => "abc123", "aspect_ratio" => "16:9"}}
      },
      attrs
    )
  end

  test "a ready Bunny video renders its stream, with Bunny's thumbnail as poster" do
    html = Parser.video(bunny(), [])

    assert html =~ "<video"
    assert html =~ ~s(https://vz-1.b-cdn.net/#{@guid}/playlist.m3u8)
    assert html =~ ~s(poster="https://vz-1.b-cdn.net/#{@guid}/thumbnail.jpg")
  end

  test "a ready Mux video renders its stream, with Mux's thumbnail as poster" do
    html = Parser.video(mux(), [])

    assert html =~ "<video"
    assert html =~ "https://stream.mux.com/abc123.m3u8"
    assert html =~ ~s(poster="https://image.mux.com/abc123/thumbnail.jpg")
  end

  test "the block's autoplay, loop and muted apply" do
    html = Parser.video(bunny(%{autoplay: true, loop: false, muted: true}), [])
    assert html =~ " autoplay"
    assert html =~ " muted"
    refute html =~ " loop"

    html = Parser.video(mux(%{autoplay: false, loop: true, controls: true}), [])
    refute html =~ " autoplay"
    assert html =~ " loop"
    assert html =~ " controls"
  end

  test "the block's poster wins over the provider's thumbnail" do
    html = Parser.video(bunny(%{poster: "https://example.com/poster.jpg"}), [])
    assert html =~ ~s(poster="https://example.com/poster.jpg")
  end

  test "a video still at the provider renders the empty comment" do
    assert Parser.video(bunny(%{status: :uploading}), []) =~ "<!-- empty video component -->"
    assert Parser.video(mux(%{status: :processing}), []) =~ "<!-- empty video component -->"
  end

  test "a 4:5 Bunny video keeps its own shape, unless the block sets one" do
    assert Parser.video(bunny(), []) =~ "--aspect-ratio-division: 1080/1350;"
    assert Parser.video(bunny(%{aspect_ratio: "16/9"}), []) =~ "--aspect-ratio-division: 16/9;"
  end

  # Bunny's 16/9 is only a guess for a video of unknown size; it beat the
  # record's own width and height. A caller's ratio still wins.
  test "Brando.HTML.video gives a Bunny video its own shape, or the caller's" do
    render = fn video, opts ->
      render_component(&Brando.HTML.Video.video/1, video: video, opts: opts)
    end

    assert render.(bunny(), []) =~ "--aspect-ratio-division: 1080/1350;"
    assert render.(bunny(), aspect_ratio: "1/1") =~ "--aspect-ratio-division: 1/1;"
    assert render.(bunny(%{width: nil, height: nil}), []) =~ "--aspect-ratio-division: 16/9;"
  end

  test "a site's own video_file_options applies" do
    refute Parser.video(bunny(), []) =~ ~s(data-progress)
    assert Parser.video(bunny(), %{parser_module: SiteParser}) =~ ~s(data-progress)
  end

  defp render_video_ref(video, block_data) do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Content.create_module(
        Factory.params_for(:module, %{
          code: "Video: {% ref refs.media %}",
          refs: [%{name: "media", uid: Utils.generate_uid(), data: %{type: "video", data: %{}}}]
        }),
        user
      )

    block = %{
      block: %{
        type: :module,
        module_id: module.id,
        uid: Utils.generate_uid(),
        vars: [],
        refs: [
          %{
            name: "media",
            description: nil,
            video_id: video.id,
            video: video,
            uid: Utils.generate_uid(),
            data: %Brando.Villain.Blocks.VideoBlock{
              type: "video",
              data: struct(Brando.Villain.Blocks.VideoBlock.Data, block_data)
            }
          }
        ]
      }
    }

    Brando.Villain.parse([block], %Brando.Pages.Page{})
  end

  defp insert_bunny(attrs \\ []) do
    Factory.insert(
      :video,
      Keyword.merge(
        [
          creator: Factory.insert(:random_user),
          type: :bunny,
          status: :ready,
          remote_id: nil,
          source_url: nil,
          width: 1080,
          height: 1350,
          meta: %{"bunny" => %{"video_guid" => @guid}}
        ],
        attrs
      )
    )
  end

  test "a video ref with a ready Bunny video renders it, with the ref's settings" do
    parsed = render_video_ref(insert_bunny(), %{autoplay: true, loop: false})

    assert parsed =~ ~s(https://vz-1.b-cdn.net/#{@guid}/playlist.m3u8)
    assert parsed =~ " autoplay"
    refute parsed =~ " loop"
    assert parsed =~ "--aspect-ratio-division: 1080/1350;"
  end

  # The library title is plain text; the ref's own title is rich text
  test "a video ref escapes the record's title, and keeps its own title's markup" do
    parsed = render_video_ref(insert_bunny(title: "<img src=x onerror=alert(1)>"), %{})
    refute parsed =~ "<img src=x"
    assert parsed =~ "<figcaption>&lt;img src=x onerror=alert(1)&gt;</figcaption>"

    parsed = render_video_ref(insert_bunny(title: "Q&A <live>"), %{})
    assert parsed =~ "<figcaption>Q&amp;A &lt;live&gt;</figcaption>"

    upload = Factory.insert(:upload_video, creator: Factory.insert(:random_user), title: "Film & co")
    assert render_video_ref(upload, %{}) =~ "<figcaption>Film &amp; co</figcaption>"

    parsed = render_video_ref(insert_bunny(title: "Q&A <live>"), %{title: "<p><strong>Tour</strong> film</p>"})
    assert parsed =~ "<figcaption><p><strong>Tour</strong> film</p></figcaption>"
  end

  test "a play button shows when autoplay is left unset" do
    assert Parser.video(bunny(%{play_button: true}), []) =~ "video-play-button"
    refute Parser.video(bunny(%{play_button: true, autoplay: true}), []) =~ "video-play-button"
  end

  test "a Vimeo account video without a file link gets the block's playback settings and size" do
    video = %Video{
      type: :vimeo_account,
      status: :ready,
      width: 1920,
      height: 1080,
      meta: %{"vimeo" => %{"video_id" => "123", "hash" => "abc"}}
    }

    html = Parser.video(%{video | autoplay: true, loop: false, aspect_ratio: "1/1"}, [])
    assert html =~ ~s(src="https://player.vimeo.com/video/123?h=abc&amp;dnt=1&amp;autoplay=1&amp;muted=1&amp;loop=0")
    assert html =~ ~s(width="1920")
    assert html =~ ~s(height="1920")

    # Vimeo's controls=0 hides its play button too: controls stay Vimeo's
    html = Parser.video(%{video | controls: false}, [])
    assert html =~ ~s(src="https://player.vimeo.com/video/123?h=abc&amp;dnt=1&amp;autoplay=0")
    refute html =~ "controls="

    # One dimension passed takes the other from the video's ratio
    html = render_component(&Brando.HTML.Video.video/1, video: video, opts: [width: 400])
    assert html =~ ~s(width="400")
    assert html =~ ~s(height="225")
  end

  # Markdown escapes the title itself; the figcaption's escaping stays out of it
  test "a video ref's title reaches the Markdown output escaped once" do
    user = Factory.insert(:random_user)
    upload = Factory.insert(:upload_video, creator: user, title: "Tom's film & co")

    {:ok, module} =
      Content.create_module(
        Factory.params_for(:module, %{
          code: "{% ref refs.media %}",
          refs: [%{name: "media", uid: Utils.generate_uid(), data: %{type: "video", data: %{}}}]
        }),
        user
      )

    block = %{
      type: :module,
      module_id: module.id,
      uid: Utils.generate_uid(),
      active: true,
      multi: false,
      children: [],
      vars: [],
      refs: [
        %{
          name: "media",
          description: nil,
          uid: Utils.generate_uid(),
          video_id: upload.id,
          video: upload,
          data: %Brando.Villain.Blocks.VideoBlock{type: "video", data: %Brando.Villain.Blocks.VideoBlock.Data{}}
        }
      ]
    }

    markdown = Brando.Villain.Markdown.render([%{block: block}], %Brando.Pages.Page{language: "en"})
    assert markdown =~ "Tom's film & co"
    refute markdown =~ "&amp;"
    refute markdown =~ "&#39;"

    # A caption cleared in the editor leaves `<p></p>`: the library title stands
    [ref] = block.refs
    cleared = %{ref | data: %{ref.data | data: %{ref.data.data | title: "<p></p>"}}}
    markdown = Brando.Villain.Markdown.render([%{block: %{block | refs: [cleared]}}], %Brando.Pages.Page{language: "en"})
    assert markdown =~ "Tom's film & co"
    refute markdown =~ "&lt;p&gt;"
  end

  # A caller's single dimension doesn't reshape the record
  test "Brando.HTML.video keeps a Bunny video's own ratio when one dimension is overridden" do
    render = fn video, opts ->
      render_component(&Brando.HTML.Video.video/1, video: video, opts: opts)
    end

    landscape = bunny(%{width: 1920, height: 1080})
    assert render.(landscape, width: 400) =~ "--aspect-ratio-division: 1920/1080;"
    assert render.(landscape, width: 400) =~ ~s(data-orientation="landscape")
    assert render.(landscape, width: 400) =~ ~s(width="400" height="225")
    assert render.(landscape, width: 400, height: 400) =~ "--aspect-ratio-division: 400/400;"
  end

  # Revision snapshots from before the field existed
  test "an old video struct without cover_image renders" do
    old = Map.delete(bunny(), :cover_image)
    assert Parser.video(old, []) =~ ~s(https://vz-1.b-cdn.net/#{@guid}/playlist.m3u8)
  end
end
