defmodule BrandoAdmin.Components.VideoURLHandler do
  @moduledoc """
  Shared helper for handling video URL parsing and creation.
  Used by both VideoInput and VideoPicker components.
  """

  @doc """
  Parse a video URL and extract relevant information
  Returns a map with video data ready for creation
  """
  def parse_video_url(url) do
    cond do
      youtube_match = Regex.run(~r/(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\s]+)/, url) ->
        [_, video_id] = youtube_match
        {:ok, %{type: :youtube, remote_id: video_id, source_url: url}}

      vimeo_match = Regex.run(~r/vimeo\.com\/(\d+)/, url) ->
        [_, video_id] = vimeo_match
        {:ok, %{type: :vimeo, remote_id: video_id, source_url: url}}

      String.match?(url, ~r/\.(mp4|webm|ogg|mov)$/i) ->
        {:ok, %{type: :external_file, source_url: url, remote_id: url}}

      true ->
        {:error, "Unsupported video URL format"}
    end
  end

  @doc """
  Create video parameters from parsed URL data and additional metadata
  """
  def build_video_params(base_params, metadata \\ %{}) do
    Map.merge(base_params, metadata)
  end

  @doc """
  Fetch OEmbed metadata if available
  """
  def fetch_oembed_metadata(type, url) when type in [:youtube, :vimeo] do
    case Brando.OEmbed.get(to_string(type), url) do
      {:ok, %{"title" => title} = oembed_data} ->
        # Extract thumbnail data and create a thumbnail struct if available
        thumbnail_data =
          case Map.get(oembed_data, "thumbnail_url") do
            nil ->
              nil

            thumbnail_url ->
              %{
                source_url: thumbnail_url,
                width: Map.get(oembed_data, "thumbnail_width"),
                height: Map.get(oembed_data, "thumbnail_height")
              }
          end

        %{
          title: title,
          width: Map.get(oembed_data, "width"),
          height: Map.get(oembed_data, "height"),
          thumbnail_url: Map.get(oembed_data, "thumbnail_url")
        }
        |> maybe_add_thumbnail_data(thumbnail_data)

      _ ->
        %{}
    end
  end

  def fetch_oembed_metadata(_, _), do: %{}

  # Helper to add thumbnail data if available
  defp maybe_add_thumbnail_data(metadata, nil), do: metadata

  defp maybe_add_thumbnail_data(metadata, thumbnail_data) do
    Map.put(metadata, :thumbnail_data, thumbnail_data)
  end

  @doc """
  Create a video record from URL
  """
  def create_video_from_url(url, user_id) do
    with {:ok, base_params} <- parse_video_url(url),
         metadata <- fetch_oembed_metadata(base_params.type, url),
         video_params <- build_video_params(base_params, metadata) do
      Brando.Videos.create_video(video_params, user_id)
    end
  end
end
