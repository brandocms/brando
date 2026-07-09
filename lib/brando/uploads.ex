defmodule Brando.Uploads do
  @moduledoc """
  Transport facade for the unified upload manager (see `docs/UPLOADER.md`).

  Transports:

  - `:server` — bytes travel through the `BrandoAdmin.UploadManager` sticky
    LiveView's own `allow_upload` and are stored via
    `Brando.Upload.handle_upload/4`. Images always; files/video on local
    storage or when the CDN config doesn't opt into direct uploads.
  - `:direct` (files → S3/Spaces, Phase 2) — the browser PUTs the bytes
    straight to the bucket via a short-lived presigned URL; the server only
    presigns at intake and creates the `File` row (`cdn: true`) at finalize,
    after verifying the object actually exists. Opt-in per config:
    `cdn: %Brando.CDN.Config{enabled: true, direct: true}`. Configs with
    `content_disposition` set stay on `:server` transport (the header can't
    ride an unsigned presigned PUT). Note: direct uploads never produce a
    local copy, regardless of `keep_local_copy`. **Ops prerequisite:** the
    bucket CORS must allow `PUT` from the admin origin.

  Intake validation happens here, *before* any bytes are transferred.
  Limits mirror what the old form-registered uploads enforced (50 MB,
  image extension allowlist); for `:server` transport, mimetype validation
  against the resolved config still runs at consume time via
  `Brando.Upload.check_mimetype` — for `:direct` it runs at intake.
  """

  use Gettext, backend: Brando.Gettext

  require Logger

  @image_exts ~w(.jpg .jpeg .png .gif .webp .svg)
  @max_file_size 50_000_000
  @presign_expiry_seconds 600

  @doc """
  Decide the transport for an intake file and prepare it.

  Returns:
  - `{:ok, :server}` — upload through the manager's `allow_upload`
  - `{:ok, {:direct, %{upload_url, key, filename, resolved_target}}}` —
    browser PUTs to `upload_url`; finalize with `finalize_direct/3`
  - `{:error, message}` — reject before any bytes move
  """
  def initiate(:file, config_target, %{name: name, size: size} = file_meta, _user) do
    with :ok <- validate_intake(:file, name, size) do
      {cfg, resolved_target} = resolve_file_config(config_target)

      if direct_transport?(cfg) do
        initiate_direct_file(cfg, resolved_target, file_meta)
      else
        {:ok, :server}
      end
    end
  end

  def initiate(asset_type, _config_target, %{name: name, size: size}, _user) do
    with :ok <- validate_intake(asset_type, name, size) do
      {:ok, :server}
    end
  end

  @doc """
  Store a consumed server-transport upload, normalizing every error shape.

  `Brando.Upload.handle_upload/4` leaks mixed error shapes from its `with`
  chain (`{:error, reason}`, `{:error, :mkdir, reason}`,
  `{:error, :content_type, type, allowed}`, ...). The upload manager consumes
  in a singleton sticky LiveView — an unmatched error shape there would crash
  the manager and kill every in-flight upload — so this facade guarantees
  `{:ok, asset} | {:error, message}` where `message` is safe to show the user.
  """
  def store_upload(meta, entry, cfg, user) do
    case Brando.Upload.handle_upload(meta, entry, cfg, user) do
      {:ok, asset} ->
        {:ok, asset}

      error ->
        Logger.error("==> Uploads: store_upload failed: #{inspect(error)}")
        {:error, format_upload_error(error)}
    end
  end

  defp format_upload_error({:error, :content_type, rejected_type, allowed_types}) do
    gettext("Rejected type [%{rejected}]. Allowed: %{allowed}", %{
      rejected: rejected_type,
      allowed: inspect(allowed_types)
    })
  end

  defp format_upload_error({:error, :mkdir, _} = error), do: upload_error_message(error)
  defp format_upload_error({:error, :cp, _} = error), do: upload_error_message(error)
  defp format_upload_error({:error, :empty_filename}), do: gettext("Empty filename")
  defp format_upload_error({:error, %Ecto.Changeset{}}), do: gettext("Could not store uploaded file")
  defp format_upload_error({:error, message}) when is_binary(message), do: message
  defp format_upload_error(error), do: inspect(error)

  defp upload_error_message(error) do
    {:error, message} = Brando.Upload.handle_upload_error(error)
    message
  end

  @doc """
  Create the asset record for a completed client-direct upload.

  Verifies the object exists in the bucket before creating the row — the
  key comes from server-side item state (never from the client), but the
  client's "complete" signal is not trusted on its own.
  """
  def finalize_direct(:file, %{key: key, resolved_target: resolved_target} = params, user) do
    {cfg, _} = resolve_file_config(resolved_target)
    cdn_config = file_cdn_config(cfg)

    if Brando.CDN.key_exists?(key, %{cdn: cdn_config}) do
      # Reuse the storage layer's :direct_to_s3 record creation so both
      # transports produce identical File rows (incl. folder_id).
      upload = %{
        cfg: cfg,
        meta: %{key: key, config_target: resolved_target, folder_id: params[:folder_id]},
        upload_entry: %{
          client_name: params[:title],
          client_type: params[:mime_type],
          client_size: params[:filesize]
        }
      }

      Brando.Upload.handle_upload_type(upload, user, :direct_to_s3)
    else
      {:error, "Uploaded object not found in bucket (#{key})"}
    end
  end

  @doc false
  # Public for testability — the decision matrix is the contract.
  def direct_transport?(cfg) do
    cdn_config = file_cdn_config(cfg)

    !!(cdn_config && cdn_config.enabled && cdn_config.direct &&
         is_nil(Map.get(cfg, :content_disposition)))
  end

  defp file_cdn_config(cfg) do
    case Map.get(cfg, :cdn) do
      %Brando.CDN.Config{} = cdn_config -> cdn_config
      _ -> normalize_cdn_config(Brando.CDN.config(Brando.Files))
    end
  end

  # App configs may give the CDN config as a struct, plain map or keyword list.
  defp normalize_cdn_config(%Brando.CDN.Config{} = cdn_config), do: cdn_config
  defp normalize_cdn_config(list) when is_list(list), do: struct(Brando.CDN.Config, list)
  defp normalize_cdn_config(%{} = map), do: struct(Brando.CDN.Config, Map.to_list(map))
  defp normalize_cdn_config(_), do: %Brando.CDN.Config{}

  defp initiate_direct_file(cfg, resolved_target, %{name: name, type: mime_type}) do
    with :ok <- validate_mimetype(cfg, mime_type) do
      filename = build_direct_filename(name, cfg)
      key = Path.join(["media", cfg.upload_path, filename])

      case presign_put(key, cfg) do
        {:ok, upload_url} ->
          {:ok, {:direct, %{upload_url: upload_url, key: key, filename: filename, resolved_target: resolved_target}}}

        {:error, reason} ->
          Logger.error("==> Uploads: presign failed for #{key}: #{inspect(reason)}")
          {:error, "Could not presign upload"}
      end
    end
  end

  # Mirror the server pipeline's filename processing (get_valid_filename +
  # ensure_correct_ext). The server dedupes on filesystem collision; we can't
  # cheaply check the bucket, so always uniquify unless the config overwrites.
  defp build_direct_filename(name, cfg) do
    cond do
      Map.get(cfg, :random_filename, false) ->
        Brando.Utils.random_filename(name)

      Map.get(cfg, :overwrite, false) ->
        maybe_slugify(name, cfg)

      true ->
        name |> maybe_slugify(cfg) |> Brando.Utils.unique_filename()
    end
    |> Brando.Utils.ensure_correct_extension()
  end

  defp maybe_slugify(name, cfg) do
    if Map.get(cfg, :slugify_filename, false) do
      Brando.Utils.slugify_filename(name)
    else
      name
    end
  end

  defp validate_mimetype(cfg, mime_type) do
    allowed = Map.get(cfg, :allowed_mimetypes) || []

    if allowed == ["*"] or mime_type in allowed do
      :ok
    else
      {:error, "Rejected file type [#{mime_type}]. Allowed: #{Enum.join(allowed, ", ")}"}
    end
  end

  @doc """
  Presign a PUT to the file CDN bucket for `key`.

  The URL is short-lived (#{@presign_expiry_seconds}s) and carries
  `x-amz-acl=public-read` as a signed query param, so the client needs no
  custom headers beyond Content-Type (which is not part of the signature).
  """
  def presign_put(key, cfg) do
    cdn_config = file_cdn_config(cfg)

    s3_config =
      %{cdn: cdn_config}
      |> Brando.CDN.get_s3_config(as: :keyword_list)
      |> Keyword.take([:access_key_id, :secret_access_key, :scheme, :host, :region])

    aws_config = ExAws.Config.new(:s3, s3_config)

    ExAws.S3.presigned_url(aws_config, :put, cdn_config.bucket, key,
      expires_in: @presign_expiry_seconds,
      query_params: [{"x-amz-acl", "public-read"}]
    )
  end

  @doc """
  Max file size accepted by the upload manager (bytes).
  """
  def max_file_size, do: @max_file_size

  @doc """
  Max number of files transferring simultaneously (per client).

  Enforced by the UploadManager JS hook for both server uploads and
  client-direct PUTs. Configure per site:

      config :brando, Brando.Uploads, max_concurrent_transfers: 2

  Defaults to 3. Set to 1 for strictly sequential transfers (the old
  gallery behavior). Queued files wait for a free slot; the drawer shows
  them as queued. Note this caps *transfer* only — image processing
  concurrency is still governed by the `:image_processing` Oban queue
  limit and `config :brando, :concurrent_image_jobs`.
  """
  def max_concurrent_transfers do
    config = Application.get_env(:brando, __MODULE__) || []
    Keyword.get(config, :max_concurrent_transfers, 3)
  end

  @doc """
  Extensions accepted for image uploads.
  """
  def image_exts, do: @image_exts

  @doc """
  Validate an intake request for a single file before any bytes move.

  Returns `:ok` or `{:error, message}` (message is safe to show the user).
  """
  def validate_intake(asset_type, filename, size)

  def validate_intake(_asset_type, _filename, size) when is_integer(size) and size > @max_file_size do
    {:error, "File is too large (max #{Brando.Utils.human_size(@max_file_size)})"}
  end

  def validate_intake(:image, filename, _size) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in @image_exts do
      :ok
    else
      {:error, "Unsupported image type [#{ext}]. Allowed: #{Enum.join(@image_exts, ", ")}"}
    end
  end

  def validate_intake(:file, _filename, _size), do: :ok

  def validate_intake(:video, filename, _size) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in ~w(.mp4 .webm .mov .avi .ogv) do
      :ok
    else
      {:error, "Unsupported video type [#{ext}]"}
    end
  end

  def validate_intake(_asset_type, _filename, _size), do: {:error, "Unsupported asset type"}

  @doc """
  Resolve an image config target to `{cfg, resolved_target}`.

  Falls back to the default image config (and `"default"` target) when the
  target has no registered config.
  """
  def resolve_image_config(config_target), do: resolve_config(Brando.Images, Brando.Type.ImageConfig, config_target)

  @doc """
  Resolve a video config target to `{cfg, resolved_target}`.

  Falls back to the default video config when unresolvable. The resolved cfg
  is guaranteed to be a `%Brando.Type.VideoConfig{}` — a plain-map cfg would
  miss the VideoConfig clause in `Brando.Upload.handle_upload_type/2` and fall
  into the generic image path.
  """
  def resolve_video_config(config_target), do: resolve_config(Brando.Videos, Brando.Type.VideoConfig, config_target)

  @doc """
  Resolve a file config target to `{cfg, resolved_target}`.

  Falls back to the default file config (and `"default"` target) when the
  target has no registered config. Note the resolved cfg may be a
  `%Brando.Type.VideoConfig{}` for `"video:"` targets (files wrapped by
  `:upload` videos resolve through the owning video asset's cfg).
  """
  def resolve_file_config(config_target), do: resolve_config(Brando.Files, Brando.Type.FileConfig, config_target)

  # Videos require the exact config struct (see resolve_video_config/1);
  # file targets may legitimately resolve to another cfg struct type.
  defp resolve_config(Brando.Videos = context, struct_mod, config_target) do
    resolved_target = normalize_config_target(config_target) || "default"

    case safe_get_config(context, resolved_target) do
      {:ok, cfg} when is_struct(cfg, struct_mod) -> {cfg, resolved_target}
      _ -> {default_config(context, struct_mod), "default"}
    end
  end

  defp resolve_config(context, struct_mod, config_target) do
    resolved_target = normalize_config_target(config_target) || "default"

    case safe_get_config(context, resolved_target) do
      {:ok, cfg} when not is_nil(cfg) -> {cfg, resolved_target}
      _ -> {default_config(context, struct_mod), "default"}
    end
  end

  defp default_config(context, struct_mod) do
    case base_default_config(context) do
      cfg when is_struct(cfg, struct_mod) -> cfg
      cfg -> struct(struct_mod, cfg)
    end
  end

  defp base_default_config(Brando.Images),
    do: Brando.config(Brando.Images)[:default_config] || Brando.Type.ImageConfig.default_config()

  defp base_default_config(Brando.Files),
    do: Brando.config(Brando.Files)[:default_config] || Brando.Type.FileConfig.default_config()

  defp base_default_config(Brando.Videos), do: Brando.config(Brando.Videos)[:default_config] || %{}

  # get_config_for raises on unknown target shapes — the upload manager must
  # never crash mid-consume over a config target, so treat any raise as
  # "unresolvable" and let the caller fall back to the default config.
  defp safe_get_config(context, resolved_target) do
    context.get_config_for(resolved_target)
  rescue
    _ -> :error
  end

  defp normalize_config_target(nil), do: nil
  defp normalize_config_target(config_target) when is_binary(config_target), do: config_target
  defp normalize_config_target(%{config_target: config_target}), do: normalize_config_target(config_target)
  defp normalize_config_target(_), do: nil
end
