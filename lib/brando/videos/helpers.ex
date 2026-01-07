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

  def get_playback_url(%Video{type: :upload, file: %{path: path}}) do
    {:ok, Brando.Utils.media_url(path)}
  end

  def get_playback_url(%Video{type: :external_file, source_url: url}) do
    {:ok, url}
  end

  def get_playback_url(%Video{}) do
    {:error, :unsupported_type}
  end
end
