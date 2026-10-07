defmodule Brando.JSONLD.Schema.VideoObject do
  @moduledoc """
  A video on the page as a schema.org `VideoObject`.

  Built from a `Brando.Videos.Video` with what the record and its provider
  already know. Google needs `name`, `thumbnailUrl` and `uploadDate` for a
  video to be eligible for video results, so `build/2` returns `nil` when any of
  them is missing rather than emitting a node Google would flag:

    * `name` — the video's title, or the title a video block gives it.
    * `thumbnailUrl` — the video's thumbnail image, else the provider's
      poster frame (Mux, Bunny, Cloudflare Stream, Vimeo). Signed Mux and
      Cloudflare videos have no public poster frame.
    * `uploadDate` — when the video was added to Brando.

  `description` (the caption), `duration` (ISO 8601), `contentUrl` (the file
  or stream) and `embedUrl` (Bunny, Vimeo and YouTube players) are added when
  known. Only ready videos are described.

  The node's `@id` is site-wide, `https://example.com/#/schema/video/<id>`,
  so a video shown on several pages is the same entity on each.
  """

  alias Brando.Utils
  alias Brando.Videos.Helpers
  alias Brando.Videos.Video
  alias Brando.Videos.VimeoURL

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "VideoObject",
            "@id": nil,
            name: nil,
            description: nil,
            thumbnailUrl: nil,
            uploadDate: nil,
            duration: nil,
            contentUrl: nil,
            embedUrl: nil,
            width: nil,
            height: nil

  @doc """
  Builds a `VideoObject` from a video, or `nil` when the video lacks a
  property Google requires.

  ## Options

    * `:name` - a title that takes precedence over the video's own, such as a
      video block's title override.
  """
  @spec build(term(), keyword()) :: t() | nil
  def build(video, opts \\ [])

  def build(%Video{status: status} = video, opts) when status in [:ready, nil] do
    node = %__MODULE__{
      "@id": id(video),
      name: present(Keyword.get(opts, :name)) || present(video.title),
      description: present(video.caption),
      thumbnailUrl: thumbnail_url(video),
      uploadDate: Brando.JSONLD.to_datetime(video.inserted_at),
      duration: duration(video.duration),
      contentUrl: content_url(video),
      embedUrl: embed_url(video),
      width: video.width,
      height: video.height
    }

    if complete?(node), do: node
  end

  def build(_video, _opts), do: nil

  @doc "The `@id` of a video's node."
  @spec id(Video.t()) :: String.t() | nil
  def id(%Video{id: id}) when not is_nil(id), do: Path.join(Utils.hostname(), "#/schema/video/#{id}")
  def id(_video), do: nil

  @doc """
  Converts Brando's `HH:MM:SS` duration (or `MM:SS`) to ISO 8601, e.g.
  `"01:02:05"` to `"PT1H2M5S"`. `nil` for anything else, and for zero.
  """
  @spec duration(term()) :: String.t() | nil
  def duration(value) when is_binary(value) do
    with {:ok, numbers} <- value |> String.trim() |> String.split(":") |> integers(),
         [hours, minutes, seconds] <- pad(numbers),
         total when total > 0 <- hours * 3600 + minutes * 60 + seconds do
      iso_duration(div(total, 3600), div(rem(total, 3600), 60), rem(total, 60))
    else
      _ -> nil
    end
  end

  def duration(_value), do: nil

  defp complete?(%__MODULE__{"@id": id, name: name, thumbnailUrl: thumbnail, uploadDate: date}),
    do: Enum.all?([id, name, thumbnail, date], &(not is_nil(&1)))

  defp integers(parts) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
      case Integer.parse(part) do
        {number, ""} when number >= 0 -> {:cont, {:ok, acc ++ [number]}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp pad([minutes, seconds]), do: [0, minutes, seconds]
  defp pad([_hours, _minutes, _seconds] = numbers), do: numbers
  defp pad(_numbers), do: nil

  defp iso_duration(hours, minutes, seconds) do
    [{hours, "H"}, {minutes, "M"}, {seconds, "S"}]
    |> Enum.reject(fn {value, _unit} -> value == 0 end)
    |> Enum.map_join(fn {value, unit} -> "#{value}#{unit}" end)
    |> then(&("PT" <> &1))
  end

  defp thumbnail_url(%Video{thumbnail: %Brando.Images.Image{} = image}) do
    case Brando.JSONLD.Schema.ImageObject.build(image) do
      %{url: url} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp thumbnail_url(video), do: video |> Helpers.thumbnail_url() |> absolute()

  defp content_url(%Video{type: :upload, file: %Brando.Files.File{}} = video), do: playback_url(video)
  defp content_url(%Video{type: :upload}), do: nil

  defp content_url(%Video{type: type} = video) when type in [:external_file, :mux, :bunny, :cloudflare, :vimeo_account],
    do: playback_url(video)

  defp content_url(_video), do: nil

  defp playback_url(video) do
    case Helpers.get_playback_url(video) do
      {:ok, url} when is_binary(url) and url != "" -> absolute(url)
      _ -> nil
    end
  end

  # Without a configured library the player URL has an empty segment.
  defp embed_url(%Video{type: :bunny} = video) do
    case Brando.Videos.Uploaders.Bunny.get_embed_url(video) do
      {:ok, url} -> if String.contains?(url, "/embed//"), do: nil, else: url
      _ -> nil
    end
  end

  defp embed_url(%Video{type: :vimeo_account} = video), do: Brando.Videos.Uploaders.Vimeo.embed_url(video)
  defp embed_url(%Video{type: :vimeo} = video), do: VimeoURL.embed_url(video)

  defp embed_url(%Video{type: :youtube, remote_id: id}) when is_binary(id) and id != "",
    do: "https://www.youtube.com/embed/#{id}"

  defp embed_url(_video), do: nil

  defp absolute("http://" <> _ = url), do: url
  defp absolute("https://" <> _ = url), do: url
  defp absolute("/" <> _ = path), do: Utils.hostname(path)
  defp absolute(_), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil
end
