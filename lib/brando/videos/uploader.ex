defmodule Brando.Videos.Uploader do
  @moduledoc """
  Behavior for video upload providers and router for upload strategies.

  ## Upload Strategy Router

  The `initiate_upload/3` function automatically routes to the appropriate
  uploader based on `config.upload_strategy`:

  - `:local` - Traditional server upload (returns error, use standard upload flow)
  - `:mux` - Routes to `Brando.Videos.Uploaders.Mux`
  - `:bunny` - Routes to `Brando.Videos.Uploaders.Bunny`
  - `:cloudflare` - Routes to `Brando.Videos.Uploaders.Cloudflare`
  - `:vimeo` - Routes to `Brando.Videos.Uploaders.Vimeo`

  ## Implementing Upload Providers

  Providers implement this behavior to handle video uploads to their service.
  Currently supported providers:
  - Mux (lib/brando/videos/uploaders/mux.ex)
  - Bunny.net (lib/brando/videos/uploaders/bunny.ex)
  - Cloudflare Stream (lib/brando/videos/uploaders/cloudflare.ex)
  - Vimeo (lib/brando/videos/uploaders/vimeo.ex)

  Unsupported strategies are rejected during Blueprint configuration rather
  than producing dead upload controls at runtime.
  """

  require Logger

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
  Lists one page of the provider's own library, newest first.

  Optional; implemented by providers that `Brando.Videos.ProviderLibrary` can
  browse. Options are `:cursor` (the previous page's `next`), `:query` and
  `:per_page`. Items are `t:Brando.Videos.ProviderLibrary.item/0` without
  `:video_id`.
  """
  @callback list_remote(opts :: keyword()) ::
              {:ok, %{items: [map()], next: term() | nil}} | {:error, any()}

  @doc """
  Creates a Video record for a video already in the provider's library.

  The record carries `meta["imported"] = true`, which keeps it out of
  `delete_remote/1`. Takes `:config_target` in `opts`.
  """
  @callback import_remote(remote_id :: String.t(), user :: user(), opts :: keyword()) ::
              {:ok, video()} | {:error, any()}

  @doc """
  The `meta` path that holds the provider's id for a video, as
  `Brando.Videos.get_video_by_meta/2` takes it — `"vimeo.video_id"`.
  """
  @callback library_meta_path() :: String.t()

  @doc "Whether `list_remote/1` honours `:query`."
  @callback library_searchable?() :: boolean()

  @doc """
  The other `meta` paths and values a record may hold the remote video at,
  for a provider whose record does not get the id at `library_meta_path/0`
  when it is created. A Mux upload has only its `mux.upload_id` until Mux
  reports the asset, so an asset made by a direct upload returns
  `[{"mux.upload_id", upload_id}]`.

  Takes the remote id, and asks the provider. The items of `list_remote/1`
  carry the same keys as `:holding_keys`, which
  `Brando.Videos.ProviderLibrary` drops from its listing.
  """
  @callback library_holding_keys(remote_id :: String.t()) ::
              {:ok, [{String.t(), String.t()}]} | {:error, any()}

  @optional_callbacks list_remote: 1,
                      import_remote: 3,
                      library_meta_path: 0,
                      library_searchable?: 0,
                      library_holding_keys: 1

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
  - `:bunny` - Direct upload to Bunny.net
  - `:vimeo` - Direct upload to Vimeo
  - `:local` - Returns error, use traditional upload flow instead

  ## Never raises

  All three callers are LiveView processes holding an editor's unsaved work, so
  an exception escaping here costs the user their edits. This function is
  therefore total: every failure comes back as `{:error, reason}`.

  Two mechanisms, and the distinction is the point:

    * **Expected** failures are validated up front by
      `Brando.Uploads.validate_provider_video_intake/2` — uploads disabled, an
      unusable strategy, missing provider credentials, size, mimetype. Nothing
      is raised and nothing is caught.
    * **Unexpected** ones — a `Req` transport failure, a JSON decode, a bug in a
      provider client — hit the rescue below. That is what a `rescue` is for.

  The rescue is here, not in a caller, so one copy covers all three call
  sites (`BrandoAdmin.Components.Form`, `VideoPicker`, `Form.Transformer`).

  Note what it deliberately does *not* catch: the providers' missing-credential
  raise. That is checked before dispatch, so rescuing it here would convert a
  decided contract straight back into the error tuple 0.54.0 removed.
  """
  def initiate_upload(filename, user, opts) when is_list(opts) do
    config = Keyword.fetch!(opts, :config)
    file_meta = Keyword.get(opts, :file_meta)

    with :ok <- Brando.Authorization.Media.authorize(user, :video),
         :ok <- Brando.Uploads.validate_provider_video_intake(config, file_meta) do
      dispatch_initiate_upload(config.upload_strategy, filename, user, opts)
    end
  end

  defp dispatch_initiate_upload(strategy, filename, user, opts) do
    case strategy do
      :mux ->
        Brando.Videos.Uploaders.Mux.initiate_upload(filename, user, opts)

      :bunny ->
        Brando.Videos.Uploaders.Bunny.initiate_upload(filename, user, opts)

      :cloudflare ->
        Brando.Videos.Uploaders.Cloudflare.initiate_upload(filename, user, opts)

      :vimeo ->
        Brando.Videos.Uploaders.Vimeo.initiate_upload(filename, user, opts)

      strategy when strategy in [:local, :s3] ->
        {:error, :use_traditional_upload}

      strategy ->
        {:error, {:unknown_strategy, strategy}}
    end
  rescue
    exception ->
      # Deliberately broad: three provider clients with three failure
      # vocabularies sit behind this call. The stacktrace is logged so a genuine
      # bug here stays diagnosable rather than being reduced to a toast, and the
      # caller gets an atom rather than `Exception.message/1` — a provider's
      # exception text is not written for an editor, and can carry request
      # detail that has no business in a browser.
      Logger.error(
        "Video provider upload raised: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      {:error, :provider_error}
  end

  @doc """
  Records that the browser finished transferring a provider upload.

  Cloudflare webhooks are terminal-only, so this moves its row from
  `:uploading` to `:processing` while encoding is underway. Vimeo has no
  webhooks at all; its row moves the same way and its status poll is nudged.
  Other providers already expose intermediate webhook states and are left
  unchanged.

  This is the browser's word, so a video with no creator (one no editor
  started) is not moved on this way: `{:error, :no_creator}`. The admin
  already takes it only for the upload token the creator was given
  (`ProviderVideoUpload`, in the admin). The provider's own
  report, which needs no creator, moves it.
  """
  def complete_client_upload(%Brando.Videos.Video{type: type, creator_id: nil})
      when type in [:cloudflare, :vimeo_account],
      do: {:error, :no_creator}

  def complete_client_upload(%Brando.Videos.Video{type: :cloudflare} = video) do
    Brando.Videos.Uploaders.Cloudflare.complete_upload(video, %{})
  end

  def complete_client_upload(%Brando.Videos.Video{type: :vimeo_account} = video) do
    Brando.Videos.Uploaders.Vimeo.complete_upload(video, %{})
  end

  def complete_client_upload(%Brando.Videos.Video{} = video), do: {:ok, video}

  @doc """
  Router function that dispatches delete_remote to the appropriate uploader.

  Determines the provider from video.meta["provider"] or video.type and calls
  the corresponding uploader's delete_remote/1 function.

  ## Parameters
  - video: The Video record to delete remotely

  ## Returns
  - `:ok` if deletion succeeds or is skipped
  - `{:error, :held_in_this_environment}` while a live record of the current
    environment plays the same remote video: added again from the provider's
    library, or the deleted record itself, restored.
  - `{:error, :held_by_another_site}` with several sites, while another site
    has a record of the same remote video, deleted or not, and
    `{:error, :held_by_another_environment}` with named environments, while
    another current environment of the site has one
    (`Brando.Videos.ProviderHoldings`). With `delete_remote_on: :on_delete`,
    another environment's soft-deleted record does not hold the video: its
    purge will not ask the provider. `{:error, :holdings_unavailable}` when
    the holdings cannot be read, and `{:error, :busy}` when an add or another
    delete of the same video held its lock too long
    (`Brando.Videos.ProviderHoldings.with_video_lock/3`). Nothing is deleted
    at the provider.
  - `{:error, reason}` if deletion fails
  """
  def delete_remote(%Brando.Videos.Video{} = video), do: delete_remote(video, fn -> :ok end)

  @doc """
  Deletes `video` at its provider as `delete_remote/1` does, then runs
  `purge`, which deletes the video's row, and returns the provider delete's
  result.

  `purge` runs while the video's lock is still held, so the row is gone
  before another environment's purge of the same video reads the holdings:
  two purges that overlap cannot each see the other's row and both leave the
  video at the provider. Outside a transaction, `purge`'s queries commit as
  they run. When the holdings cannot be read or the lock is busy
  (`{:error, :holdings_unavailable}`, `{:error, :busy}`), `purge` does not
  run, and the row stays for the next purge to try again.
  """
  @spec delete_remote(Brando.Videos.Video.t(), (-> term())) :: :ok | {:error, term()}
  # Added from the provider's library: someone else's video, possibly in use
  # elsewhere. Brando forgets it but does not delete it.
  def delete_remote(%Brando.Videos.Video{meta: %{"imported" => true}}, purge), do: then_purge(:ok, purge)

  def delete_remote(%Brando.Videos.Video{} = video, purge) do
    case library_remote_id(video) do
      {module, remote_id} when is_binary(remote_id) ->
        # An add or a restore of the same video waits, and this waits for one
        # in progress, so the check below still holds when the provider is
        # asked.
        Brando.Videos.ProviderHoldings.with_video_lock(module.library_meta_path(), remote_id, fn ->
          video |> delete_unless_held(module, remote_id, Brando.Tenant.mode()) |> then_purge(purge)
        end)

      _no_remote_id ->
        video |> dispatch_delete_remote() |> then_purge(purge)
    end
  end

  defp then_purge({:error, reason} = result, _purge) when reason in [:holdings_unavailable, :busy], do: result

  defp then_purge(result, purge) do
    purge.()
    result
  end

  defp delete_unless_held(video, module, remote_id, mode) do
    case held(video, module, remote_id, mode) do
      false ->
        dispatch_delete_remote(video)

      {:held_by_another_environment = reason, prefixes} ->
        Logger.info(
          "Video #{video.id} left at its provider: held_by_another_environment, " <>
            "still recorded in #{Enum.join(prefixes, ", ")}"
        )

        {:error, reason}

      reason ->
        Logger.info("Video #{video.id} left at its provider: #{reason}")
        {:error, reason}
    end
  end

  # A live record of this environment plays the video: added again from the
  # provider's library while this one waited for its purge, or this one, read
  # deleted and restored since. Its own delete will ask the provider again.
  defp held(video, module, remote_id, mode) do
    except_id = if is_nil(video.deleted_at), do: video.id

    cond do
      Brando.Videos.ProviderHoldings.recorded_here?(module.library_meta_path(), remote_id, except_id) ->
        :held_in_this_environment

      mode in [:single, :multi] ->
        held_elsewhere(video, module, remote_id, mode)

      true ->
        false
    end
  end

  # An environment copied from another has the same remote videos, and with
  # several sites another site may hold one too: added from the provider's
  # library, or uploaded before the sites stopped sharing. Deleting it at the
  # provider would break the other record, so it stays there, and so it does
  # when that cannot be told. With one site, only its own environments are
  # read.
  #
  # Another site's record holds the video, deleted or not. So does another
  # environment's of the same site, unless the video is deleted remotely
  # `:on_delete`: that environment's purge will not ask the provider, so its
  # soft-deleted record would keep the video there for good.
  defp held_elsewhere(video, module, remote_id, mode) do
    prefix = Brando.Tenant.current_prefix()
    site_key = Brando.Tenant.site_key_of(prefix)
    sites = Brando.Tenant.Registry.list_sites()
    own_site_id = Enum.find_value(sites, &(&1.key == site_key && &1.id))
    sites = if mode == :single, do: Enum.filter(sites, &(&1.key == site_key)), else: sites
    deleted_hold_own? = get_delete_timing(video) != :on_delete

    case Brando.Videos.ProviderHoldings.environments_holding(module.library_meta_path(), [remote_id], sites) do
      {:ok, holders} ->
        others =
          holders
          |> Map.get(remote_id, MapSet.new())
          |> Enum.reject(fn {_site_id, held_in, _deleted?} -> held_in == prefix end)

        {own_site, other_sites} = Enum.split_with(others, fn {site_id, _prefix, _deleted?} -> site_id == own_site_id end)
        own_site = Enum.filter(own_site, fn {_site_id, _prefix, deleted?} -> deleted_hold_own? or not deleted? end)

        cond do
          other_sites != [] -> :held_by_another_site
          own_site != [] -> {:held_by_another_environment, own_site |> Enum.map(&elem(&1, 1)) |> Enum.sort()}
          true -> false
        end

      {:error, _reason} ->
        :holdings_unavailable
    end
  end

  defp library_remote_id(video) do
    with provider when not is_nil(provider) <- get_provider(video),
         module = provider_module(provider),
         path = String.split(module.library_meta_path(), "."),
         remote_id when is_binary(remote_id) <- get_in(video.meta || %{}, path) do
      {module, remote_id}
    end
  end

  defp provider_module(:mux), do: Brando.Videos.Uploaders.Mux
  defp provider_module(:bunny), do: Brando.Videos.Uploaders.Bunny
  defp provider_module(:cloudflare), do: Brando.Videos.Uploaders.Cloudflare
  defp provider_module(:vimeo), do: Brando.Videos.Uploaders.Vimeo

  defp dispatch_delete_remote(video) do
    case get_provider(video) do
      :mux ->
        Brando.Videos.Uploaders.Mux.delete_remote(video)

      :bunny ->
        Brando.Videos.Uploaders.Bunny.delete_remote(video)

      :cloudflare ->
        Brando.Videos.Uploaders.Cloudflare.delete_remote(video)

      :vimeo ->
        Brando.Videos.Uploaders.Vimeo.delete_remote(video)

      _ ->
        :ok
    end
  end

  @doc """
  Returns the configured delete_remote_on value for the video's provider.

  ## Returns
  - `:on_delete` - Delete immediately on soft-delete
  - `:on_purge` - Delete when soft-delete expires (default)
  - `false` - Never delete remotely, and always for a video added from the
    provider's library (see `Brando.Videos.ProviderLibrary`)
  """
  def get_delete_timing(%Brando.Videos.Video{meta: %{"imported" => true}}), do: false

  def get_delete_timing(%Brando.Videos.Video{} = video) do
    uploader =
      case get_provider(video) do
        :mux -> Brando.Videos.Uploaders.Mux
        :bunny -> Brando.Videos.Uploaders.Bunny
        :cloudflare -> Brando.Videos.Uploaders.Cloudflare
        :vimeo -> Brando.Videos.Uploaders.Vimeo
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
  defp get_provider(%{type: :cloudflare}), do: :cloudflare
  defp get_provider(%{type: :vimeo_account}), do: :vimeo
  defp get_provider(_), do: nil
end
