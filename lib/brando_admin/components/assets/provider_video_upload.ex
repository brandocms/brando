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
  #   * `video_upload_complete`: `complete/2`, then the component takes the
  #     video the way it takes a picked one, if it still shows what it showed
  #     when the upload started (`remember/4`, `still_shown?/4`). Otherwise
  #     the video stays in the library only.
  #
  # The browser never names the video it completes. `ready_payload/4` signs,
  # into the destination it pushes, a token naming the video, the user and the
  # request (`upload_token`); the hook sends it back with `request_ref`, and
  # `complete/2` takes the video only from a token this user was given for
  # that request, for a video they created.
  #   * `video_upload_progress`, `upload_error`: nothing; both show
  #     client-side, in the field and the upload drawer.
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, send_update: 2]

  alias Brando.Uploads.AssetIntent
  alias BrandoAdmin.Components.Assets.MediaField

  @token_salt "brando-provider-video-upload"
  # As long as `Brando.Worker.VideoUploadReaper` leaves an upload in flight.
  @token_max_age 86_400

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
      {:ok, result} ->
        push_event(socket, "video_upload_url_ready", ready_payload(result, user, filename, request_ref))

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
  The `video_upload_url_ready` payload for an initiated upload: the
  provider's destination, and the `upload_token` the hook completes with.
  """
  def ready_payload(%{upload_url: upload_url, video: video} = result, user, filename, request_ref) do
    Map.merge(
      %{
        upload_url: upload_url,
        video_id: video.id,
        filename: filename,
        request_ref: request_ref,
        upload_token: upload_token(video, user, request_ref)
      },
      Map.take(result, [:tus_auth])
    )
  end

  @doc """
  Signs the upload of `video`, started by `user` for `request_ref`.
  """
  def upload_token(video, user, request_ref) do
    Phoenix.Token.sign(Brando.endpoint(), @token_salt, %{video_id: video.id, user_id: user_id(user), ref: request_ref})
  end

  @doc """
  The file is with the provider: completes the upload where the provider
  needs it, and returns the video, or `{:error, reason}` from the provider.
  Only for a `video_upload_complete` whose `upload_token` was signed for this
  user and this `request_ref` (`ready_payload/4`), for a video the user
  created; anything else is `:error` and the video is left alone. `preload`
  is passed to the lookup.
  """
  def complete(user, params, preload \\ [])

  def complete(user, %{"upload_token" => token, "request_ref" => request_ref}, preload)
      when is_binary(token) and is_binary(request_ref) do
    case uploaded_video(user_id(user), token, request_ref, preload) do
      {:ok, video} -> Brando.Videos.Uploader.complete_client_upload(video)
      :error -> :error
    end
  end

  def complete(_user, _params, _preload), do: :error

  @doc """
  The user a provider upload event acts for: the view's actor, else the
  component's `current_user`.
  """
  def actor(socket), do: BrandoAdmin.Authorization.current_actor() || socket.assigns[:current_user]

  defp uploaded_video(nil, _token, _request_ref, _preload), do: :error

  defp uploaded_video(user_id, token, request_ref, preload) do
    with {:ok, %{video_id: video_id, user_id: ^user_id, ref: ^request_ref}} <-
           Phoenix.Token.verify(Brando.endpoint(), @token_salt, token, max_age: @token_max_age),
         {:ok, %{creator_id: ^user_id} = video} <-
           Brando.Videos.get_video(%{matches: %{id: video_id}, preload: preload}) do
      {:ok, video}
    else
      _ -> :error
    end
  end

  defp user_id(%Brando.Authorization.Scope{user_id: id}), do: id
  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
