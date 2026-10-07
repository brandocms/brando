defmodule Brando.JSONLD.Schema.VideoObjectTest do
  # Bunny's player and poster URLs read application config.
  use ExUnit.Case, async: false

  alias Brando.JSONLD.Schema.VideoObject
  alias Brando.Videos.Video

  @uploaded ~N[2026-03-04 10:20:30]

  # Google's required VideoObject properties.
  @required ~w(name thumbnailUrl uploadDate)a

  defp video(attrs) do
    struct(
      %Video{
        id: 7,
        status: :ready,
        title: "Studio visit",
        caption: "A walk through the studio",
        duration: "00:01:05",
        width: 1920,
        height: 1080,
        inserted_at: @uploaded,
        meta: %{}
      },
      attrs
    )
  end

  defp assert_required(node) do
    for property <- @required, do: assert(is_binary(Map.fetch!(node, property)), "#{property} is missing")
    node
  end

  describe "providers" do
    test "Mux: the poster frame and stream from the playback id" do
      node =
        [type: :mux, meta: %{"mux" => %{"playback_id" => "abc123"}}]
        |> video()
        |> VideoObject.build()
        |> assert_required()

      assert node."@id" == "http://localhost/#/schema/video/7"
      assert node.name == "Studio visit"
      assert node.description == "A walk through the studio"
      assert node.thumbnailUrl == "https://image.mux.com/abc123/thumbnail.jpg"
      assert node.uploadDate == "2026-03-04T10:20:30Z"
      assert node.duration == "PT1M5S"
      assert node.contentUrl == "https://stream.mux.com/abc123.m3u8"
      assert node.embedUrl == nil
    end

    test "Bunny: the poster frame, stream and player from the video guid" do
      previous = Application.get_env(:brando, Brando.Videos.Uploaders.Bunny)
      Application.put_env(:brando, Brando.Videos.Uploaders.Bunny, cdn_hostname: "vz-test.b-cdn.net", library_id: "42")
      on_exit(fn -> restore(Brando.Videos.Uploaders.Bunny, previous) end)

      node =
        [type: :bunny, duration: "01:02:03", meta: %{"bunny" => %{"video_guid" => "guid-1"}}]
        |> video()
        |> VideoObject.build()
        |> assert_required()

      assert node.thumbnailUrl == "https://vz-test.b-cdn.net/guid-1/thumbnail.jpg"
      assert node.contentUrl == "https://vz-test.b-cdn.net/guid-1/playlist.m3u8"
      assert node.embedUrl == "https://iframe.mediadelivery.net/embed/42/guid-1"
      assert node.duration == "PT1H2M3S"
    end

    test "Cloudflare Stream: the stored poster frame and HLS manifest" do
      meta = %{
        "cloudflare" => %{
          "uid" => "cf-1",
          "thumbnail_url" => "https://customer-x.cloudflarestream.com/cf-1/thumbnails/thumbnail.jpg",
          "playback_hls" => "https://customer-x.cloudflarestream.com/cf-1/manifest/video.m3u8"
        }
      }

      node = [type: :cloudflare, meta: meta] |> video() |> VideoObject.build() |> assert_required()

      assert node.thumbnailUrl == "https://customer-x.cloudflarestream.com/cf-1/thumbnails/thumbnail.jpg"
      assert node.contentUrl == "https://customer-x.cloudflarestream.com/cf-1/manifest/video.m3u8"
    end

    test "Vimeo: the stored poster frame, file link and player with its hash" do
      meta = %{
        "vimeo" => %{
          "video_id" => "123456",
          "hash" => "abcdef",
          "thumbnail_url" => "https://i.vimeocdn.com/video/1_1280.jpg",
          "hls_url" => "https://player.vimeo.com/external/123456.m3u8"
        }
      }

      node = [type: :vimeo_account, meta: meta] |> video() |> VideoObject.build() |> assert_required()

      assert node.thumbnailUrl == "https://i.vimeocdn.com/video/1_1280.jpg"
      assert node.contentUrl == "https://player.vimeo.com/external/123456.m3u8"
      assert node.embedUrl == "https://player.vimeo.com/video/123456?h=abcdef"
    end

    test "a thumbnail image on the video wins over the provider's poster frame" do
      image = %Brando.Images.Image{
        path: "images/videos/thumbnails/poster.jpg",
        sizes: %{"xlarge" => "images/videos/thumbnails/xlarge/poster.jpg"},
        width: 2100,
        height: 1181
      }

      node =
        [type: :mux, thumbnail: image, meta: %{"mux" => %{"playback_id" => "abc123"}}]
        |> video()
        |> VideoObject.build()

      assert node.thumbnailUrl == "http://localhost/media/images/videos/thumbnails/xlarge/poster.jpg"
    end

    test "a block's title names the video" do
      node =
        [type: :mux, title: nil, meta: %{"mux" => %{"playback_id" => "abc123"}}]
        |> video()
        |> VideoObject.build(name: "From the block")

      assert node.name == "From the block"
    end
  end

  describe "missing required properties" do
    test "no node without a name" do
      assert [type: :mux, title: "  ", meta: %{"mux" => %{"playback_id" => "abc"}}] |> video() |> VideoObject.build() ==
               nil
    end

    test "no node without a thumbnail" do
      assert [type: :youtube, remote_id: "dQw4w9WgXcQ"] |> video() |> VideoObject.build() == nil
      assert [type: :bunny, meta: %{"bunny" => %{"video_guid" => "g"}}] |> video() |> VideoObject.build() == nil
    end

    test "no node for signed playback, which has no public poster frame" do
      meta = %{"mux" => %{"playback_id" => "abc", "playback_policy" => "signed"}}
      assert [type: :mux, meta: meta] |> video() |> VideoObject.build() == nil
    end

    test "no node without an upload date or for a video that is not ready" do
      mux = %{"mux" => %{"playback_id" => "abc"}}
      assert [type: :mux, inserted_at: nil, meta: mux] |> video() |> VideoObject.build() == nil
      assert [type: :mux, status: :processing, meta: mux] |> video() |> VideoObject.build() == nil
    end

    test "no node for anything that is not a video" do
      assert VideoObject.build(nil) == nil
      assert VideoObject.build(%Ecto.Association.NotLoaded{}) == nil
    end
  end

  test "durations convert to ISO 8601" do
    assert VideoObject.duration("00:00:42") == "PT42S"
    assert VideoObject.duration("02:00:00") == "PT2H"
    assert VideoObject.duration("3:07") == "PT3M7S"
    assert VideoObject.duration("00:00:00") == nil
    assert VideoObject.duration("about a minute") == nil
    assert VideoObject.duration("1:02:03:04") == nil
    assert VideoObject.duration(nil) == nil
  end

  defp restore(key, nil), do: Application.delete_env(:brando, key)
  defp restore(key, value), do: Application.put_env(:brando, key, value)
end
