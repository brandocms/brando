defmodule Brando.Videos.Playback do
  @moduledoc """
  Which source a video plays from: streamed over HLS, or a progressive MP4 at
  one resolution. `Brando.HTML.video/1` asks this for every Bunny and Mux video, and
  `Brando.Villain.Parser` renders provider videos through `Brando.HTML.video/1`,
  so a template and a block can't pick different files for the same inputs.

  ## Quality

  A video's `quality` is one of `qualities/0`:

    * `:auto`: HLS when the video has controls or a play button, since someone
      may watch it through; otherwise the MP4 at the site's default resolution,
      which reaches its first frame sooner for an autoplaying loop.
    * `:hls`: always the stream.
    * `:mp4_270` to `:mp4_2160`: that MP4. A resolution the video lacks falls
      back to the next one down, and to the stream when the video has no MP4s.
      Which resolutions there can be depends on the provider: Bunny makes 360p
      to 1080p (`bunny_resolutions/0`), Mux 270p to 2160p (`mux_resolutions/0`).

  ## Precedence

  The editor's choice wins over the template's: the record's `quality`, which
  a video block, ref or gallery object overrides for its placement, then the
  `quality:` option a template passes, then `:auto`. nil at a level inherits
  from the next.

  ## Site default

  `:auto` plays MP4s at

      config :brando, Brando.Videos, default_mp4_resolution: 720

  which is the default.

  ## Bunny

  Bunny serves `play_{360,480,720,1080}p.mp4` next to the stream when the
  library's **MP4 Fallback** encoding setting was on when the video was
  uploaded. Its API reports that as `hasMP4Fallback`, stored in
  `meta.bunny.has_mp4_fallback`. Only `true` offers MP4s: a video stored before
  Brando kept the flag streams until it is refreshed (`Brando.Videos.fetch_metadata/2`).

  ## Mux

  Mux serves a static rendition at `https://stream.mux.com/{playback_id}/{resolution}p.mp4`
  once it is ready. Brando asks for the ones in

      config :brando, Brando.Videos, mux_static_renditions: [720, 1080]

  (the default) when it creates an asset, and keeps what Mux reports of them in
  `meta.mux.static_renditions`. Only renditions Mux reports as `ready` are
  offered, and the `highest` rendition older uploads asked for is not used.
  An older asset that would play an MP4 streams until
  `Brando.Videos.Uploaders.Mux.add_static_renditions/1`
  (`mix brando.videos.mux_renditions`) has asked Mux for the configured ones.
  """

  use Gettext, backend: Brando.Gettext

  alias Brando.Videos.Video

  @bunny_resolutions [360, 480, 720, 1080]
  @mux_resolutions [270, 360, 480, 540, 720, 1080, 1440, 2160]
  @mp4_resolutions Enum.sort(Enum.uniq(@bunny_resolutions ++ @mux_resolutions))
  @mp4_qualities Map.new(@mp4_resolutions, &{&1, :"mp4_#{&1}"})
  @qualities [:auto, :hls | Enum.map(@mp4_resolutions, &@mp4_qualities[&1])]
  @default_mp4_resolution 720

  @type quality ::
          :auto | :hls | :mp4_270 | :mp4_360 | :mp4_480 | :mp4_540 | :mp4_720 | :mp4_1080 | :mp4_1440 | :mp4_2160
  @type format :: :hls | :mp4

  @doc "Every quality, in the order an editor chooses from."
  @spec qualities() :: [quality()]
  def qualities, do: @qualities

  @doc "The MP4 resolutions Bunny's MP4 Fallback can make, lowest first."
  @spec bunny_resolutions() :: [pos_integer()]
  def bunny_resolutions, do: @bunny_resolutions

  @doc "The static rendition resolutions Mux can make, lowest first."
  @spec mux_resolutions() :: [pos_integer()]
  def mux_resolutions, do: @mux_resolutions

  @doc """
  A quality from a stored or passed value: an atom, its string as a form or a
  gallery object's config holds it, or nil and "" for none. Anything else is
  none.
  """
  @spec normalize(term()) :: quality() | nil
  def normalize(quality) when quality in @qualities, do: quality
  def normalize(quality) when is_binary(quality), do: Enum.find(@qualities, &(Atom.to_string(&1) == quality))
  def normalize(_quality), do: nil

  @doc """
  The qualities an editor can choose from for `video`, empty for a video
  without renditions to choose from (an upload, a linked file, YouTube). The
  MP4s are the ones the video has, so a Bunny video without MP4 Fallback, or
  a Mux video without ready static renditions, has Automatic and Streaming
  only.
  """
  @spec choices(Video.t() | nil) :: [quality()]
  def choices(%Video{type: type} = video) when type in [:bunny, :mux],
    do: [:auto, :hls | Enum.map(mp4_resolutions(video), &@mp4_qualities[&1])]

  def choices(_video), do: []

  @doc "What an editor reads for `quality`."
  @spec label(quality()) :: String.t()
  def label(:auto), do: gettext("Automatic")
  def label(:hls), do: gettext("Streaming (HLS)")
  def label(quality), do: gettext("MP4, %{resolution}p", resolution: requested_resolution(quality))

  @doc """
  The MP4 resolutions `video` has, lowest first.
  """
  @spec mp4_resolutions(Video.t() | nil) :: [pos_integer()]
  def mp4_resolutions(%Video{type: :bunny, meta: %{"bunny" => %{"has_mp4_fallback" => true} = bunny}}) do
    bunny |> Map.get("available_resolutions") |> parse_resolutions(@bunny_resolutions)
  end

  # Signed playback renders nothing, so it has no MP4s to offer either
  def mp4_resolutions(%Video{type: :mux, meta: %{"mux" => %{"playback_policy" => "signed"}}}), do: []

  def mp4_resolutions(%Video{type: :mux, meta: %{"mux" => %{"static_renditions" => renditions}}})
      when is_list(renditions) do
    renditions
    |> Enum.flat_map(fn
      %{"status" => "ready", "resolution" => resolution} -> [resolution]
      _ -> []
    end)
    |> parse_resolutions(@mux_resolutions)
  end

  def mp4_resolutions(_video), do: []

  # Bunny lists them as "240p,360p,720p"
  defp parse_resolutions(resolutions, known) when is_binary(resolutions),
    do: resolutions |> String.split(",") |> parse_resolutions(known)

  defp parse_resolutions(resolutions, known) when is_list(resolutions) do
    resolutions
    |> Enum.flat_map(fn resolution ->
      case Integer.parse(String.trim(to_string(resolution))) do
        {height, rest} when rest in ["", "p"] -> [height]
        _ -> []
      end
    end)
    |> Enum.filter(&(&1 in known))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_resolutions(_resolutions, _known), do: []

  @doc """
  The quality `video` plays at: its own, then the template's, then `:auto`.
  """
  @spec quality(Video.t(), term()) :: quality()
  def quality(%Video{} = video, template_quality) do
    normalize(Map.get(video, :quality)) || normalize(template_quality) || :auto
  end

  @doc """
  The source `video` plays from, as `{format, url}`.

  ## Options

    * `:quality` - the template's quality, beaten by the record's
    * `:controls`, `:play_button` - whether the player shows them, which
      decides `:auto`
  """
  @spec source(Video.t(), keyword()) :: {format(), String.t()}
  def source(%Video{type: :bunny} = video, opts) do
    case mp4_resolution(video, opts) do
      nil -> {:hls, bunny_url(video, "playlist.m3u8")}
      resolution -> {:mp4, bunny_url(video, "play_#{resolution}p.mp4")}
    end
  end

  def source(%Video{type: :mux} = video, opts) do
    playback_id = get_in(video.meta, ["mux", "playback_id"])

    case mp4_resolution(video, opts) do
      nil -> {:hls, "https://stream.mux.com/#{playback_id}.m3u8"}
      resolution -> {:mp4, "https://stream.mux.com/#{playback_id}/#{resolution}p.mp4"}
    end
  end

  # The resolution to play, or nil for the stream
  defp mp4_resolution(video, opts) do
    case quality(video, Keyword.get(opts, :quality)) do
      :hls -> nil
      :auto -> if watched?(opts), do: nil, else: closest(mp4_resolutions(video), default_mp4_resolution())
      quality -> closest(mp4_resolutions(video), requested_resolution(quality))
    end
  end

  defp watched?(opts),
    do: Keyword.get(opts, :controls) not in [nil, false] or Keyword.get(opts, :play_button) not in [nil, false]

  defp requested_resolution(quality) do
    Enum.find_value(@mp4_qualities, fn {resolution, mp4_quality} -> mp4_quality == quality && resolution end)
  end

  # The requested resolution, else the next one down, else the lowest there is
  defp closest([], _requested), do: nil

  defp closest([lowest | _] = resolutions, requested) do
    resolutions |> Enum.filter(&(&1 <= requested)) |> List.last() || lowest
  end

  @doc """
  The resolution `:auto` plays MP4s at: `config :brando, Brando.Videos,
  default_mp4_resolution: 720`, the default.
  """
  @spec default_mp4_resolution() :: pos_integer()
  def default_mp4_resolution do
    case :brando |> Application.get_env(Brando.Videos, []) |> Keyword.get(:default_mp4_resolution) do
      resolution when is_integer(resolution) and resolution > 0 -> resolution
      _ -> @default_mp4_resolution
    end
  end

  defp bunny_url(%Video{meta: meta}, file) do
    "https://#{bunny_cdn_hostname()}/#{get_in(meta, ["bunny", "video_guid"])}/#{file}"
  end

  defp bunny_cdn_hostname do
    :brando
    |> Application.get_env(Brando.Videos.Uploaders.Bunny, [])
    |> Keyword.get(:cdn_hostname, "")
  end
end
