defmodule Brando.Videos.Uploader do
  @moduledoc """
  Behavior for video upload providers and router for upload strategies.

  ## Upload Strategy Router

  The `initiate_upload/3` function automatically routes to the appropriate
  uploader based on `config.upload_strategy`:

  - `:local` - Traditional server upload (returns error, use standard upload flow)
  - `:mux` - Routes to `Brando.Videos.Uploaders.Mux`
  - `:bunny` - Routes to `Brando.Videos.Uploaders.Bunny`
  - `:cloudflare` - Routes to Cloudflare Stream uploader (not yet implemented)
  - `:s3` - Routes to AWS S3 uploader (not yet implemented)

  ## Implementing Upload Providers

  Providers implement this behavior to handle video uploads to their service.
  Currently supported providers:
  - Mux (lib/brando/videos/uploaders/mux.ex)
  - Bunny.net (lib/brando/videos/uploaders/bunny.ex)

  Future providers:
  - Vimeo
  - Cloudflare Stream
  - YouTube (upload API)
  - AWS S3
  """

  @type video :: Brando.Videos.Video.t()
  @type user :: Brando.Users.User.t()
  @type config :: Brando.Type.VideoConfig.t()
  @type upload_result :: %{
          upload_url: String.t(),
          video: video(),
          expires_at: DateTime.t() | nil
        }

  @doc """
  Initiate an upload process.

  Creates a Video record with `:uploading` status and returns a signed upload URL
  where the client can upload the file directly.

  ## Parameters
  - filename: Original filename from client
  - user: Current user initiating upload
  - opts: Provider-specific options

  ## Returns
  - `{:ok, upload_result}` with upload_url and created video record
  - `{:error, reason}` if upload initiation fails
  """
  @callback initiate_upload(
              filename :: String.t(),
              user :: user(),
              opts :: keyword()
            ) :: {:ok, upload_result()} | {:error, any()}

  @doc """
  Complete an upload after the file has been uploaded to the provider.

  Updates the Video record with final provider data (asset ID, playback URL, etc.)
  and sets status to `:processing` or `:ready`.

  ## Parameters
  - video: The Video record created during initiation
  - provider_data: Data returned from provider after upload completes

  ## Returns
  - `{:ok, updated_video}` with provider metadata in the :meta field
  - `{:error, reason}` if completion fails
  """
  @callback complete_upload(video :: video(), provider_data :: map()) ::
              {:ok, video()} | {:error, any()}

  @doc """
  Handle webhook callbacks from the provider.

  Processes webhook events (e.g., "video.asset.ready", "video.processing.failed")
  and updates the Video record accordingly.

  ## Parameters
  - payload: Webhook payload from provider

  ## Returns
  - `{:ok, updated_video}` if webhook was processed
  - `:ignore` if webhook event is not relevant
  - `{:error, reason}` if webhook processing fails
  """
  @callback handle_webhook(payload :: map()) ::
              {:ok, video()} | :ignore | {:error, any()}

  @doc """
  Delete a video from the provider's service.

  Removes the video asset from the provider (e.g., deletes Mux asset).
  Should be called when a Video record is soft-deleted or permanently deleted.

  ## Parameters
  - video: The Video record to delete remotely

  ## Returns
  - `:ok` if deletion succeeds or asset doesn't exist
  - `{:error, reason}` if deletion fails
  """
  @callback delete_remote(video :: video()) :: :ok | {:error, any()}

  @doc """
  Get the playback URL for a video.

  Returns the URL where the video can be played (e.g., HLS manifest URL).

  ## Parameters
  - video: The Video record

  ## Returns
  - `{:ok, url}` with playback URL
  - `{:error, reason}` if video isn't ready or playback URL unavailable
  """
  @callback get_playback_url(video :: video()) ::
              {:ok, String.t()} | {:error, any()}

  @doc """
  Router function that dispatches to the appropriate uploader based on config.upload_strategy.

  ## Parameters
  - filename: Original filename from client
  - user: Current user initiating upload
  - opts: Options including `:config` (required for routing)

  ## Returns
  - `{:ok, upload_result}` with upload_url and created video record
  - `{:error, reason}` if upload initiation fails or strategy is unsupported

  ## Examples

      # Route to Mux uploader
      {:ok, config} = Brando.Videos.get_config_for("video:MyApp.MediaItem:video")
      Brando.Videos.Uploader.initiate_upload("video.mp4", user, config: config)

  ## Upload Strategies

  - `:mux` - Direct upload to Mux
  - `:cloudflare` - Direct upload to Cloudflare Stream (not yet implemented)
  - `:s3` - Direct upload to AWS S3 (not yet implemented)
  - `:bunny` - Direct upload to Bunny.net (not yet implemented)
  - `:local` - Returns error, use traditional upload flow instead
  """
  def initiate_upload(filename, user, opts) when is_list(opts) do
    config = Keyword.fetch!(opts, :config)

    case config.upload_strategy do
      :mux ->
        Brando.Videos.Uploaders.Mux.initiate_upload(filename, user, opts)

      :cloudflare ->
        {:error, :not_implemented}

      :s3 ->
        {:error, :not_implemented}

      :bunny ->
        Brando.Videos.Uploaders.Bunny.initiate_upload(filename, user, opts)

      :local ->
        {:error, :use_traditional_upload}

      strategy ->
        {:error, {:unknown_strategy, strategy}}
    end
  end

  @doc """
  Router function that dispatches delete_remote to the appropriate uploader.

  Determines the provider from video.meta["provider"] or video.type and calls
  the corresponding uploader's delete_remote/1 function.

  ## Parameters
  - video: The Video record to delete remotely

  ## Returns
  - `:ok` if deletion succeeds or is skipped
  - `{:error, reason}` if deletion fails
  """
  def delete_remote(%Brando.Videos.Video{} = video) do
    case get_provider(video) do
      :mux ->
        Brando.Videos.Uploaders.Mux.delete_remote(video)

      :bunny ->
        Brando.Videos.Uploaders.Bunny.delete_remote(video)

      _ ->
        :ok
    end
  end

  @doc """
  Returns the configured delete_remote_on value for the video's provider.

  ## Returns
  - `:on_delete` - Delete immediately on soft-delete
  - `:on_purge` - Delete when soft-delete expires (default)
  - `false` - Never delete remotely
  """
  def get_delete_timing(%Brando.Videos.Video{} = video) do
    uploader =
      case get_provider(video) do
        :mux -> Brando.Videos.Uploaders.Mux
        :bunny -> Brando.Videos.Uploaders.Bunny
        _ -> nil
      end

    if uploader do
      config = Application.get_env(:brando, uploader, [])
      Keyword.get(config, :delete_remote_on, :on_purge)
    else
      false
    end
  end

  defp get_provider(%{type: :mux}), do: :mux
  defp get_provider(%{type: :bunny}), do: :bunny
  defp get_provider(_), do: nil
end
