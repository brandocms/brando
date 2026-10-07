defmodule Brando.JSONLD.Videos do
  @moduledoc """
  Finds the videos an entry shows, for its JSON-LD `video` property.

  Two places are read, both only as far as they are already loaded — nothing
  here queries the database:

    * the blueprint's video fields (`asset :cover_video, :video`), when the
      video is preloaded;
    * the entry's block fields, when their blocks and refs are preloaded:
      every active ref with a video, in active blocks and their children. A
      video block's title override names the video.

  Each video becomes a `Brando.JSONLD.Schema.VideoObject`, or nothing when it
  lacks a property Google requires (see that module). A video shown twice is
  described once.
  """

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.JSONLD.Schema.VideoObject
  alias Brando.Videos.Video
  alias Brando.Villain.Blocks.VideoBlock

  @doc """
  The `VideoObject`s for the videos `entry` shows, in page order: video
  fields first, then blocks.
  """
  @spec from_entry(module(), map()) :: [VideoObject.t()]
  def from_entry(module, entry) when is_atom(module) and is_map(entry) do
    (field_videos(module, entry) ++ block_videos(module, entry))
    |> Enum.map(fn {video, opts} -> VideoObject.build(video, opts) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1."@id")
  end

  def from_entry(_module, _entry), do: []

  defp field_videos(module, entry) do
    if function_exported?(module, :__video_fields__, 0) do
      for %{name: name} <- module.__video_fields__(),
          %Video{} = video <- [Map.get(entry, name)],
          do: {video, []}
    else
      []
    end
  end

  defp block_videos(module, entry) do
    if function_exported?(module, :__blocks_fields__, 0) do
      Enum.flat_map(module.__blocks_fields__(), fn %{name: name} ->
        entry
        |> Map.get(:"entry_#{name}")
        |> loaded_list()
        |> Enum.flat_map(&entry_block_videos/1)
      end)
    else
      []
    end
  end

  defp entry_block_videos(%{block: %Block{} = block}), do: videos_in_block(block)
  defp entry_block_videos(_entry_block), do: []

  defp videos_in_block(%Block{active: false}), do: []

  defp videos_in_block(%Block{} = block) do
    ref_videos = block.refs |> loaded_list() |> Enum.flat_map(&ref_video/1)
    child_videos = block.children |> loaded_list() |> Enum.flat_map(&videos_in_block/1)
    ref_videos ++ child_videos
  end

  defp videos_in_block(_block), do: []

  defp ref_video(%Ref{active: false}), do: []
  defp ref_video(%Ref{video: %Video{} = video, data: %VideoBlock{data: %{title: title}}}), do: [{video, [name: title]}]
  defp ref_video(%Ref{video: %Video{} = video}), do: [{video, []}]
  defp ref_video(_ref), do: []

  defp loaded_list(list) when is_list(list), do: list
  defp loaded_list(_not_loaded), do: []
end
