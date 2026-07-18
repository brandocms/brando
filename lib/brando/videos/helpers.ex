defmodule Brando.Videos.Helpers do
  @moduledoc """
  Helper functions for working with Brando.Videos.Video records.
  """

  alias Brando.Videos.Video

  @doc """
  Get a value from the video's provider-specific meta.

  ## Examples

      iex> get_meta_field(video, "mux", "asset_id")
      "abc123"

      iex> get_meta_field(video, "mux", "nonexistent")
      nil
  """
  def get_meta_field(%Video{meta: meta}, provider, key) do
    get_in(meta, [provider, key])
  end

  @doc """
  Update a video's provider-specific meta field.

  ## Examples

      iex> put_meta_field(video, "mux", "asset_id", "abc123")
      %Video{meta: %{"provider" => "mux", "mux" => %{"asset_id" => "abc123"}}}
  """
  def put_meta_field(%Video{meta: meta} = video, provider, key, value) do
    provider_meta = Map.get(meta, provider, %{})
    updated_provider_meta = Map.put(provider_meta, key, value)
    updated_meta = Map.put(meta, provider, updated_provider_meta)

    %{video | meta: updated_meta}
  end

  @doc """
  Get the Mux asset ID from a video.
  """
  def get_mux_asset_id(video) do
    get_meta_field(video, "mux", "asset_id")
  end

  @doc """
  Get the Mux playback ID from a video.
  """
  def get_mux_playback_id(video) do
    get_meta_field(video, "mux", "playback_id")
  end

  @doc """
  Get the playback URL for a video using its provider.

  ## Examples

      iex> get_playback_url(%Video{type: :mux, meta: %{"mux" => %{"playback_id" => "xyz"}}, status: :ready})
      {:ok, "https://stream.mux.com/xyz.m3u8"}
  """
  def get_playback_url(%Video{type: :mux} = video) do
    Brando.Videos.Uploaders.Mux.get_playback_url(video)
  end

  def get_playback_url(%Video{type: :bunny} = video) do
    Brando.Videos.Uploaders.Bunny.get_playback_url(video)
  end

  def get_playback_url(%Video{type: :cloudflare} = video) do
    Brando.Videos.Uploaders.Cloudflare.get_playback_url(video)
  end

  def get_playback_url(%Video{type: :upload, file: %Brando.Files.File{} = file}) do
    {:ok, Brando.Utils.media_url(file)}
  end

  def get_playback_url(%Video{type: :upload, remote_id: remote_id}) when is_binary(remote_id) do
    {:ok, Brando.Utils.media_url() <> "/" <> remote_id}
  end

  def get_playback_url(%Video{type: :upload}) do
    {:error, :file_not_loaded}
  end

  def get_playback_url(%Video{type: :external_file, source_url: url}) when is_binary(url) do
    {:ok, url}
  end

  def get_playback_url(%Video{type: :external_file}) do
    {:error, :missing_source_url}
  end

  def get_playback_url(%Video{}) do
    {:error, :unsupported_type}
  end

  @doc """
  Get the thumbnail URL for a video.

  Returns the URL as a string or nil if no thumbnail is available.

  ## Examples

      iex> thumbnail_url(%Video{thumbnail: %Image{path: "images/thumb.jpg"}})
      "/media/images/thumb.jpg"

      iex> thumbnail_url(%Video{type: :mux, meta: %{"mux" => %{"playback_id" => "xyz"}}})
      "https://image.mux.com/xyz/thumbnail.jpg"

      iex> thumbnail_url(%Video{type: :youtube})
      nil
  """
  def thumbnail_url(%Video{thumbnail: %Brando.Images.Image{} = img}) do
    Brando.Utils.media_url(img.path)
  end

  def thumbnail_url(%Video{type: :mux, meta: %{"mux" => %{"playback_policy" => "signed"}}}), do: nil

  def thumbnail_url(%Video{type: :mux, meta: %{"mux" => %{"playback_id" => playback_id}}})
      when is_binary(playback_id) do
    "https://image.mux.com/#{playback_id}/thumbnail.jpg"
  end

  def thumbnail_url(%Video{type: :bunny, meta: %{"bunny" => %{"video_guid" => guid}}})
      when is_binary(guid) do
    cdn_hostname = get_bunny_cdn_hostname()

    if cdn_hostname != "" do
      "https://#{cdn_hostname}/#{guid}/thumbnail.jpg"
    else
      nil
    end
  end

  def thumbnail_url(%Video{type: :cloudflare, meta: %{"cloudflare" => %{"require_signed_urls" => true}}}),
    do: nil

  def thumbnail_url(%Video{type: :cloudflare, meta: %{"cloudflare" => %{"thumbnail_url" => url}}})
      when is_binary(url),
      do: url

  def thumbnail_url(%Video{}), do: nil

  @doc """
  Formats a provider duration in seconds as an `HH:MM:SS` string.
  """
  @spec format_duration(number()) :: String.t()
  def format_duration(seconds) when is_number(seconds) do
    total_seconds = round(seconds)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    remaining_seconds = rem(total_seconds, 60)

    Enum.map_join([hours, minutes, remaining_seconds], ":", &String.pad_leading(to_string(&1), 2, "0"))
  end

  @doc """
  Attempt to derive a thumbnail URL from an external file video's source URL
  by matching against known provider URL patterns.

  Currently supports:
    - Bunny CDN Stream: `https://vz-*.b-cdn.net/{guid}/playlist.m3u8`
  """
  def derive_external_thumbnail_url(%Video{type: :external_file, source_url: url})
      when is_binary(url) do
    derive_external_thumbnail(url)
  end

  def derive_external_thumbnail_url(_), do: nil

  defp derive_external_thumbnail(url) do
    cond do
      # Bunny CDN Stream: https://vz-*.b-cdn.net/{guid}/playlist.m3u8
      String.contains?(url, ".b-cdn.net/") and String.ends_with?(url, "/playlist.m3u8") ->
        String.replace_trailing(url, "/playlist.m3u8", "/thumbnail.jpg")

      # Mux Stream: https://stream.mux.com/{playback_id}.m3u8
      String.starts_with?(url, "https://stream.mux.com/") ->
        case Regex.run(~r{https://stream\.mux\.com/([^/.]+)}, url) do
          [_, playback_id] -> "https://image.mux.com/#{playback_id}/thumbnail.jpg"
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp get_bunny_cdn_hostname do
    :brando
    |> Application.get_env(Brando.Videos.Uploaders.Bunny, [])
    |> Keyword.get(:cdn_hostname, "")
  end
end
