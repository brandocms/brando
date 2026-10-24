defmodule BrandoAdmin.Components.Assets.ProviderVideoUpload do
  @moduledoc false
  # A video field, ref or var whose config uploads to a provider (Mux, Bunny,
  # Cloudflare, Vimeo) takes an upload itself: it renders the provider's
  # upload hook (`hook/1`), passes the hook's id to `MediaField.field/1` as
  # `video_hook_id`, and answers the hook's events:
  #
  #   * `get_video_upload_url`: `initiate/4` creates the video with the
  #     component's config target and pushes the provider's destination. A
  #     component that doesn't know the editor (a ref, a var) asks the video
  #     picker to do it (`initiate_in_picker/3`), which does.
  #   * `video_upload_complete`: `complete/1`, then the component takes the
  #     video the way it takes a picked one, if it still shows what it showed
  #     when the upload started (`remember/4`, `still_shown?/4`). Otherwise
  #     the video stays in the library only.
  #   * `video_upload_progress`, `upload_error`: nothing; both show
  #     client-side, in the field and the upload drawer.
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, send_update: 2]

  alias Brando.Uploads.AssetIntent
  alias BrandoAdmin.Components.Assets.MediaField

  @doc """
  The provider upload hook for a config target's strategy, when it is a
  provider with credentials; nil otherwise.
  """
  def hook(config_target) do
    {cfg, _target} = Brando.Uploads.resolve_video_config(config_target)

    if Brando.Uploads.video_upload_available?(cfg), do: MediaField.video_uploader_hook(cfg.upload_strategy)
  end

  @doc """
  Creates the video for a `get_video_upload_url` request, with the config
  target's config, and pushes the provider's destination to the hook, or why
  there is none.
  """
  def initiate(
        socket,
        user,
        config_target,
        %{"request_ref" => request_ref, "filename" => filename, "size" => size, "mime_type" => mime_type}
      ) do
    {cfg, config_target} = Brando.Uploads.resolve_video_config(config_target)

    case Brando.Videos.Uploader.initiate_upload(filename, user,
           config: cfg,
           config_target: config_target,
           file_meta: %{name: filename, size: size, type: mime_type}
         ) do
      {:ok, %{upload_url: upload_url, video: video} = result} ->
        payload =
          Map.merge(
            %{upload_url: upload_url, video_id: video.id, filename: filename, request_ref: request_ref},
            Map.take(result, [:tus_auth])
          )

        push_event(socket, "video_upload_url_ready", payload)

      {:error, reason} ->
        push_event(socket, "video_upload_url_error", %{
          error: Brando.Uploads.video_upload_error_message(reason),
          filename: filename,
          request_ref: request_ref
        })
    end
  end

  def initiate(socket, _user, _config_target, params) do
    push_event(socket, "video_upload_url_error", %{
      error: gettext("Invalid video upload request"),
      filename: Map.get(params, "filename", ""),
      request_ref: Map.get(params, "request_ref", "")
    })
  end

  @doc """
  Hands a `get_video_upload_url` request to the video picker, which knows the
  editor, to `initiate/4` with this config target.
  """
  def initiate_in_picker(config_target, params) do
    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      provider_upload: %{config_target: config_target, params: params}
    )
  end

  @doc """
  Records, for a `get_video_upload_url` request, what the component shows
  now: its video's id, and for a var its key.
  """
  def remember(socket, %{"request_ref" => request_ref}, video_id, key) do
    shown = Map.put(socket.assigns[:provider_uploads] || %{}, request_ref, {video_id || "none", key})
    assign(socket, :provider_uploads, shown)
  end

  def remember(socket, _params, _video_id, _key), do: socket

  @doc """
  Forgets the request, and returns whether the component still shows what it
  did when the request came (`remember/4`). A request it has no record of (it
  mounted again since) counts as shown.
  """
  def still_shown?(socket, request_ref, video_id, key) do
    {shown, uploads} = Map.pop(socket.assigns[:provider_uploads] || %{}, request_ref)

    still_shown? =
      case shown do
        nil -> true
        {expected_id, expected_key} -> expected_key == key and AssetIntent.current_selection?(expected_id, video_id)
      end

    {still_shown?, assign(socket, :provider_uploads, uploads)}
  end

  @doc """
  The file is with the provider: completes the upload where the provider
  needs it, and returns the video.
  """
  def complete(video_id) do
    with {:ok, video} <- Brando.Videos.get_video(video_id),
         {:ok, video} <- Brando.Videos.Uploader.complete_client_upload(video) do
      {:ok, video}
    else
      _ -> :error
    end
  end
end
