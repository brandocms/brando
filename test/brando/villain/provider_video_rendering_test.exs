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

  test "a video ref with a ready Bunny video renders it, with the ref's settings" do
    user = Factory.insert(:random_user)

    video =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :ready,
        remote_id: nil,
        source_url: nil,
        width: 1080,
        height: 1350,
        meta: %{"bunny" => %{"video_guid" => @guid}}
      )

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
              data: %Brando.Villain.Blocks.VideoBlock.Data{autoplay: true, loop: false}
            }
          }
        ]
      }
    }

    parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

    assert parsed =~ ~s(https://vz-1.b-cdn.net/#{@guid}/playlist.m3u8)
    assert parsed =~ " autoplay"
    refute parsed =~ " loop"
    assert parsed =~ "--aspect-ratio-division: 1080/1350;"
  end
end
