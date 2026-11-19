defmodule Brando.Videos.Mp4Use do
  @moduledoc """
  Which videos would play an MP4 somewhere, by what Brando stores: the
  video's own settings and those of each place an entry shows it
  (`Brando.Content.Usage.placements/2`), a block's ref, a variable, an asset
  field, or a gallery with its object's config and a gallery block's override.

  A place plays an MP4 when its quality, its own or else the video's, is a
  fixed MP4 (`:mp4_720`), or when it is Automatic (or unset) and the place
  autoplays without controls or a play button (`Brando.Videos.Playback`). A
  video whose own quality is a fixed MP4 plays one too, wherever it is.

  What a template passes (`{% video entry.video { autoplay: true } %}`) is
  not stored, so a video that loops only because its template says so is not
  seen: set autoplay on the video or its placement.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Usage
  alias Brando.Galleries.GalleryObject
  alias Brando.Videos.Playback
  alias Brando.Videos.Video
  alias Brando.Villain.Parser

  @doc "The ids of `videos` that would play an MP4 somewhere."
  @spec video_ids([Video.t()]) :: MapSet.t(integer())
  def video_ids([]), do: MapSet.new()

  def video_ids(videos) do
    ids = Enum.map(videos, & &1.id)
    placements = :video |> Usage.placements(ids) |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    gallery_ids = for {_id, places} <- placements, {:gallery, gallery_id} <- places, uniq: true, do: gallery_id
    galleries = galleries(gallery_ids, ids)

    for video <- videos, plays_mp4?(video, Map.get(placements, video.id, []), galleries), into: MapSet.new(), do: video.id
  end

  defp plays_mp4?(video, places, galleries) do
    fixed_mp4?(settings(video)) or
      Enum.any?(places, fn place -> video |> place_settings(place, galleries) |> Enum.any?(&plays_mp4?/1) end)
  end

  # For each gallery holding one of the videos: how entries show it (its
  # placements) and the videos' objects in it, with their config
  defp galleries([], _video_ids), do: %{}

  defp galleries(gallery_ids, video_ids) do
    places = :gallery |> Usage.placements(gallery_ids) |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    objects =
      from(o in GalleryObject,
        where: o.gallery_id in ^gallery_ids and o.video_id in ^video_ids,
        select: {o.gallery_id, o.video_id, o.config}
      )
      |> Brando.Repo.all()
      |> Enum.group_by(&{elem(&1, 0), elem(&1, 1)}, &(elem(&1, 2) || %{}))

    Map.new(gallery_ids, &{&1, %{places: Map.get(places, &1, []), objects: objects}})
  end

  defp settings(%Video{} = video) do
    %{quality: video.quality, autoplay: video.autoplay, controls: video.controls, play_button: false}
  end

  # The settings each placement plays with, one or more
  defp place_settings(video, :direct, _galleries), do: [settings(video)]

  defp place_settings(video, {:ref, data}, _galleries), do: [ref_settings(settings(video), block_data(data))]

  defp place_settings(video, {:gallery, gallery_id}, galleries) do
    %{places: places, objects: objects} = Map.fetch!(galleries, gallery_id)
    configs = Map.get(objects, {gallery_id, video.id}, [])

    # As the renderer does: a gallery block's override first, then the
    # object's config on top of it (`Brando.Villain.Parser`)
    Enum.flat_map(configs, fn config ->
      places
      |> Enum.flat_map(&gallery_place_settings(settings(video), &1, video.id, length(configs)))
      |> Enum.map(&Parser.apply_video_config(&1, config))
    end)
  end

  defp block_data(%{"type" => "media", "data" => %{"template_video" => %{} = data}}), do: data
  defp block_data(%{"data" => %{} = data}), do: data
  defp block_data(_data), do: %{}

  # A block's ref: nil inherits the video's, and a play button shows only
  # without autoplay (`Brando.Villain.Parser.video_file_options/1`)
  defp ref_settings(base, data) do
    autoplay = inherit(data["autoplay"], base.autoplay)

    %{
      quality: Playback.normalize(data["quality"]) || base.quality,
      autoplay: autoplay,
      controls: inherit(data["controls"], base.controls),
      play_button: data["play_button"] == true and autoplay != true
    }
  end

  defp inherit(nil, base), do: base
  defp inherit(value, _base), do: value

  # A gallery shown as it is, or through a gallery block's ref, whose
  # overrides for the video apply to it. A placement without one plays the
  # video's own, unless one override covers each placement.
  defp gallery_place_settings(base, :direct, _video_id, _count), do: [base]

  defp gallery_place_settings(base, {:ref, data}, video_id, count) do
    overrides =
      data
      |> block_data()
      |> Map.get("gallery_object_overrides")
      |> List.wrap()
      |> Enum.filter(&video_override?(&1, video_id))

    covered? = Enum.any?(overrides, &is_nil(&1["placement"])) or length(overrides) >= count
    from_overrides = Enum.map(overrides, &override_settings(base, &1))

    if covered?, do: from_overrides, else: [base | from_overrides]
  end

  defp gallery_place_settings(_base, _place, _video_id, _count), do: []

  defp video_override?(%{"object_id" => id} = override, video_id),
    do: override["object_type"] in [nil, "video"] and to_string(id) == to_string(video_id)

  defp video_override?(_override, _video_id), do: false

  # `Brando.Villain.Parser`'s gallery overrides: a `use_default_*` flag keeps
  # the video's, as does no flag and no value
  defp override_settings(base, override) do
    %{
      base
      | quality: Playback.normalize(override["quality"]) || base.quality,
        autoplay: override_value(override, "autoplay", base.autoplay),
        controls: override_value(override, "controls", base.controls)
    }
  end

  defp override_value(override, key, base) do
    case {override["use_default_#{key}"], override[key]} do
      {true, _value} -> base
      {_flag, value} when is_boolean(value) -> value
      _ -> base
    end
  end

  defp fixed_mp4?(%{quality: quality}), do: Playback.normalize(quality) not in [nil, :auto, :hls]

  defp plays_mp4?(settings) do
    case Playback.normalize(settings.quality) do
      :hls ->
        false

      quality when quality in [nil, :auto] ->
        settings.autoplay == true and settings.controls != true and not settings.play_button

      _mp4 ->
        true
    end
  end
end
