defmodule Brando.Uploads do
  @moduledoc """
  Transport facade for the unified upload manager (see `docs/UPLOADER.md`).

  Transports:

  - `:server` — bytes travel through the `BrandoAdmin.UploadManager` sticky
    LiveView's own `allow_upload` and are stored via
    `Brando.Upload.handle_upload/4`. Images always; files/video on local
    storage or when the CDN config doesn't opt into direct uploads.
  - `:direct` (files/videos → S3-compatible storage) — the browser PUTs the bytes
    straight to the bucket via a short-lived presigned URL; the server only
    presigns at intake and creates a `File` row (`cdn: true`) — plus its
    wrapping `Video` for video uploads — at finalize, after verifying the
    object's size and content type. Opt-in per config:
    `cdn: %Brando.CDN.Config{enabled: true, direct: true}`. Configs with
    `content_disposition` set stay on `:server` transport (the header can't
    ride an unsigned presigned PUT). Note: direct uploads never produce a
    local copy, regardless of `keep_local_copy`. **Ops prerequisite:** the
    bucket CORS must allow `PUT` from the admin origin.

  Intake validation happens here, *before* any bytes are transferred.
  The size ceiling is the resolved field config's `:size_limit`, falling
  back to a global 50 MB default (plus an image extension allowlist);
  for `:server` transport, mimetype validation
  against the resolved config still runs at consume time via
  `Brando.Upload.check_mimetype` — for `:direct` it runs at intake.
  """

  use Gettext, backend: Brando.Gettext

  alias Brando.Utils

  require Logger

  @image_exts ~w(.jpg .jpeg .png .gif .webp .svg)
  @max_file_size 50_000_000
  # This is the Phoenix transport envelope, not the per-asset authorization
  # limit. Intake resolves the target config and applies its size_limit before
  # any bytes move. Keep the envelope comfortably above normal media configs;
  # installations accepting larger source files can raise it explicitly.
  @manager_max_file_size 5_000_000_000
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
    {cfg, resolved_target} = resolve_file_config(config_target)

    with :ok <- validate_intake(:file, name, size, size_limit(cfg)) do
      if direct_transport?(cfg) do
        initiate_direct_file(cfg, resolved_target, file_meta)
      else
        {:ok, :server}
      end
    end
  end

  def initiate(:image, config_target, %{name: name, size: size}, _user) do
    {cfg, _} = resolve_image_config(config_target)

    with :ok <- validate_intake(:image, name, size, size_limit(cfg)) do
      {:ok, :server}
    end
  end

  def initiate(:video, config_target, %{name: name, size: size} = file_meta, _user) do
    {cfg, resolved_target} = resolve_video_config(config_target)

    with :ok <- validate_upload_enabled(cfg),
         :ok <- validate_intake(:video, name, size, size_limit(cfg)),
         :ok <- validate_optional_mimetype(cfg, Map.get(file_meta, :type), name) do
      case cfg.upload_strategy do
        :local ->
          {:ok, :server}

        :s3 ->
          if direct_video_transport?(cfg) do
            initiate_direct_asset(cfg, resolved_target, file_meta)
          else
            {:error, "S3 video uploads require an enabled direct CDN configuration"}
          end

        strategy ->
          {:error, "Video upload strategy #{inspect(strategy)} does not use the upload manager"}
      end
    end
  end

  # Catch-all. The clauses above claim every asset type `validate_intake/3` can
  # answer `:ok` for, so this one is only ever reached with a type it rejects —
  # there is no success path left to guard, and the error it returns is the
  # single source of that message.
  def initiate(asset_type, _config_target, %{name: name, size: size}, _user) do
    validate_intake(asset_type, name, size)
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

  defp format_upload_error({:error, %Ecto.Changeset{}}),
    do: gettext("Could not store uploaded file")

  defp format_upload_error({:error, message}) when is_binary(message), do: message
  defp format_upload_error(error), do: inspect(error)

  defp upload_error_message(error) do
    {:error, message} = Brando.Upload.handle_upload_error(error)
    message
  end

  @doc """
  Create the asset record for a completed client-direct upload.

  Verifies the object's size and content type before creating the row — the key
  and expected metadata come from server-side item state (never from the
  completion event), so the client's "complete" signal is not trusted alone.
  """
  def finalize_direct(:file, %{key: key, resolved_target: resolved_target} = params, user) do
    {cfg, _} = resolve_file_config(resolved_target)
    cdn_config = file_cdn_config(cfg)

    with {:ok, object} <- Brando.CDN.head_object(key, %{cdn: cdn_config}),
         :ok <- validate_direct_object(object, params[:filesize], params[:mime_type]) do
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
      {:error, :not_found} -> {:error, "Uploaded object not found in bucket (#{key})"}
      {:error, reason} -> {:error, reason}
    end
  end

  def finalize_direct(:video, %{key: key, resolved_target: resolved_target} = params, user) do
    {cfg, _} = resolve_video_config(resolved_target)
    cdn_config = video_cdn_config(cfg)

    with true <- direct_video_transport?(cfg),
         {:ok, object} <- Brando.CDN.head_object(key, %{cdn: cdn_config}),
         :ok <- validate_direct_object(object, params[:filesize], params[:mime_type]) do
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
      false -> {:error, "S3 video CDN is not configured for direct uploads"}
      {:error, :not_found} -> {:error, "Uploaded object not found in bucket (#{key})"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def validate_direct_object(%{headers: headers}, expected_size, expected_mime_type)
      when is_list(headers) do
    normalized_headers =
      Map.new(headers, fn {key, value} ->
        {key |> to_string() |> String.downcase(), to_string(value)}
      end)

    with :ok <- validate_direct_size(normalized_headers["content-length"], expected_size),
         :ok <- validate_direct_mimetype(normalized_headers["content-type"], expected_mime_type) do
      :ok
    end
  end

  def validate_direct_object(_response, _expected_size, _expected_mime_type),
    do: {:error, "Uploaded object metadata is unavailable"}

  @doc false
  # Public for testability — the decision matrix is the contract.
  def direct_transport?(cfg) do
    cdn_config = file_cdn_config(cfg)

    !!(cdn_config && cdn_config.enabled && cdn_config.direct &&
         is_nil(Map.get(cfg, :content_disposition)))
  end

  @doc false
  def direct_video_transport?(%{upload_strategy: :s3} = cfg) do
    case video_cdn_config(cfg) do
      %Brando.CDN.Config{
        enabled: true,
        direct: true,
        bucket: bucket,
        media_url: media_url
      }
      when is_binary(bucket) and bucket != "" and is_binary(media_url) and media_url != "" ->
        true

      _ ->
        false
    end
  end

  def direct_video_transport?(_cfg), do: false

  @doc false
  def video_upload_available?(%{allow_uploads: true, upload_strategy: :local}), do: true
  def video_upload_available?(%{allow_uploads: true, upload_strategy: :s3} = cfg), do: direct_video_transport?(cfg)

  def video_upload_available?(%{allow_uploads: true, upload_strategy: strategy}) do
    Brando.Videos.upload_available?(strategy)
  end

  def video_upload_available?(_cfg), do: false

  defp file_cdn_config(cfg) do
    case Map.get(cfg, :cdn) do
      %Brando.CDN.Config{} = cdn_config -> cdn_config
      list when is_list(list) -> normalize_cdn_config(list)
      %{} = map -> normalize_cdn_config(map)
      _ -> normalize_cdn_config(Brando.CDN.config(Brando.Files))
    end
  end

  defp video_cdn_config(cfg) do
    case Map.get(cfg, :cdn) do
      %Brando.CDN.Config{} = cdn_config -> cdn_config
      list when is_list(list) -> normalize_cdn_config(list)
      %{} = map -> normalize_cdn_config(map)
      _ -> nil
    end
  end

  # App configs may give the CDN config as a struct, plain map or keyword list.
  defp normalize_cdn_config(%Brando.CDN.Config{} = cdn_config), do: cdn_config
  defp normalize_cdn_config(list) when is_list(list), do: struct(Brando.CDN.Config, list)
  defp normalize_cdn_config(%{} = map), do: struct(Brando.CDN.Config, Map.to_list(map))
  defp normalize_cdn_config(_), do: %Brando.CDN.Config{}

  defp initiate_direct_file(cfg, resolved_target, file_meta) do
    initiate_direct_asset(cfg, resolved_target, file_meta)
  end

  defp initiate_direct_asset(cfg, resolved_target, %{name: name, type: mime_type}) do
    with :ok <- validate_mimetype(cfg, mime_type) do
      filename = build_direct_filename(name, cfg)
      key = Path.join(["media", cfg.upload_path, filename])

      case presign_put(key, cfg, mime_type: mime_type) do
        {:ok, %{upload_url: upload_url, headers: headers}} ->
          {:ok,
           {:direct,
            %{
              upload_url: upload_url,
              upload_headers: headers,
              key: key,
              filename: filename,
              resolved_target: resolved_target
            }}}

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
        Utils.random_filename(name)

      Map.get(cfg, :overwrite, false) ->
        maybe_slugify(name, cfg)

      true ->
        name |> maybe_slugify(cfg) |> Utils.unique_filename()
    end
    |> Utils.ensure_correct_extension()
  end

  defp maybe_slugify(name, cfg) do
    if Map.get(cfg, :slugify_filename, false) do
      Utils.slugify_filename(name)
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

  The URL is short-lived (#{@presign_expiry_seconds}s). `Content-Type` is a
  signed header. An object ACL is included only when the CDN config explicitly
  sets `direct_acl`; modern AWS buckets should keep this nil and use a bucket
  policy instead.
  """
  def presign_put(key, cfg, opts \\ []) do
    cdn_config = file_cdn_config(cfg)
    mime_type = Keyword.get(opts, :mime_type, "application/octet-stream")
    headers = presign_headers(cdn_config, mime_type)

    s3_config =
      %{cdn: cdn_config}
      |> Brando.CDN.get_s3_config(as: :keyword_list)
      |> Keyword.take([:access_key_id, :secret_access_key, :scheme, :host, :region])

    aws_config = ExAws.Config.new(:s3, s3_config)

    case ExAws.S3.presigned_url(aws_config, :put, cdn_config.bucket, key,
           expires_in: @presign_expiry_seconds,
           headers: headers
         ) do
      {:ok, upload_url} -> {:ok, %{upload_url: upload_url, headers: Map.new(headers)}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Validate a browser-to-provider video upload against its resolved config.

  Provider transfers do not pass through Phoenix's upload consumer, so this is
  their authoritative size, extension, MIME type, strategy, and feature gate.
  """
  def validate_provider_video_intake(cfg, %{name: name, size: size} = file_meta) do
    with :ok <- validate_upload_enabled(cfg),
         :ok <- validate_provider_strategy(cfg),
         :ok <- validate_intake(:video, name, size, size_limit(cfg)),
         :ok <- validate_optional_mimetype(cfg, Map.get(file_meta, :type), name) do
      :ok
    end
  end

  def validate_provider_video_intake(_cfg, _file_meta),
    do: {:error, "Invalid video upload metadata"}

  @doc """
  Max file size accepted by the upload manager (bytes).
  """
  def max_file_size, do: @max_file_size

  @doc """
  Maximum payload accepted by the UploadManager's Phoenix transport.

  This is only a transport backstop. `initiate/4` remains authoritative and
  enforces the resolved image/file/video config's `size_limit` first.

      config :brando, Brando.Uploads,
        manager_max_file_size: 10_000_000_000
  """
  def manager_max_file_size do
    config = Application.get_env(:brando, __MODULE__) || []
    Keyword.get(config, :manager_max_file_size, @manager_max_file_size)
  end

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

  `size_limit` comes from the resolved field config's `:size_limit` (see
  `Brando.Blueprint.Assets`), falling back to the global
  #{@max_file_size} byte ceiling when the config doesn't set one.

  Returns `:ok` or `{:error, message}` (message is safe to show the user).
  """
  def validate_intake(asset_type, filename, size, size_limit \\ @max_file_size)

  def validate_intake(_asset_type, _filename, size, _size_limit)
      when not is_integer(size) or size < 0 do
    {:error, "Invalid file size"}
  end

  def validate_intake(_asset_type, _filename, size, size_limit)
      when is_integer(size) and is_integer(size_limit) and size > size_limit do
    {:error, "File is too large (max #{Utils.human_size(size_limit)})"}
  end

  def validate_intake(:image, filename, _size, _size_limit) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in @image_exts do
      :ok
    else
      {:error, "Unsupported image type [#{ext}]. Allowed: #{Enum.join(@image_exts, ", ")}"}
    end
  end

  def validate_intake(:file, _filename, _size, _size_limit), do: :ok

  def validate_intake(:video, filename, _size, _size_limit) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in ~w(.mp4 .webm .mov .avi .ogv) do
      :ok
    else
      {:error, "Unsupported video type [#{ext}]"}
    end
  end

  def validate_intake(_asset_type, _filename, _size, _size_limit),
    do: {:error, "Unsupported asset type"}

  defp validate_upload_enabled(%{allow_uploads: true}), do: :ok
  defp validate_upload_enabled(_cfg), do: {:error, "Video uploads are disabled for this field"}

  defp validate_provider_strategy(%{upload_strategy: strategy})
       when strategy in [:mux, :bunny, :cloudflare],
       do: :ok

  defp validate_provider_strategy(%{upload_strategy: strategy}),
    do: {:error, "Video upload strategy #{inspect(strategy)} is not available for provider uploads"}

  defp validate_optional_mimetype(cfg, mime_type, filename) do
    effective_mime_type =
      case mime_type do
        value when is_binary(value) and value != "" -> value
        _ -> inferred_video_mimetype(filename)
      end

    validate_mimetype(cfg, effective_mime_type)
  end

  defp inferred_video_mimetype(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".mp4" -> "video/mp4"
      ".webm" -> "video/webm"
      ".mov" -> "video/quicktime"
      ".avi" -> "video/x-msvideo"
      ".ogv" -> "video/ogg"
      _ -> "application/octet-stream"
    end
  end

  defp presign_headers(cdn_config, mime_type) do
    [{"content-type", mime_type}]
    |> maybe_add_acl_header(Map.get(cdn_config, :direct_acl))
  end

  defp maybe_add_acl_header(headers, acl) when acl in [nil, false, ""], do: headers
  defp maybe_add_acl_header(headers, acl) when is_atom(acl), do: maybe_add_acl_header(headers, Atom.to_string(acl))
  defp maybe_add_acl_header(headers, acl) when is_binary(acl), do: headers ++ [{"x-amz-acl", acl}]

  defp validate_direct_size(nil, _expected_size),
    do: {:error, "Uploaded object is missing Content-Length metadata"}

  defp validate_direct_size(content_length, expected_size) when is_integer(expected_size) do
    case Integer.parse(content_length) do
      {^expected_size, ""} -> :ok
      {actual_size, ""} -> {:error, "Uploaded object size mismatch (expected #{expected_size}, got #{actual_size})"}
      _ -> {:error, "Uploaded object has invalid Content-Length metadata"}
    end
  end

  defp validate_direct_size(_content_length, _expected_size),
    do: {:error, "Expected upload size is invalid"}

  defp validate_direct_mimetype(nil, _expected_mime_type),
    do: {:error, "Uploaded object is missing Content-Type metadata"}

  defp validate_direct_mimetype(content_type, expected_mime_type) when is_binary(expected_mime_type) do
    actual_mime_type = content_type |> String.split(";", parts: 2) |> hd() |> String.trim()

    if actual_mime_type == expected_mime_type do
      :ok
    else
      {:error, "Uploaded object type mismatch (expected #{expected_mime_type}, got #{actual_mime_type})"}
    end
  end

  defp validate_direct_mimetype(_content_type, _expected_mime_type),
    do: {:error, "Expected upload type is invalid"}

  defp size_limit(cfg) do
    case Map.get(cfg, :size_limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      _ -> @max_file_size
    end
  end

  @doc """
  Resolve an image config target to `{cfg, resolved_target}`.

  Falls back to the default image config (and `"default"` target) when the
  target has no registered config.
  """
  def resolve_image_config(config_target),
    do: resolve_config(Brando.Images, Brando.Type.ImageConfig, config_target)

  @doc """
  Resolve a video config target to `{cfg, resolved_target}`.

  Falls back to the default video config when unresolvable. The resolved cfg
  is guaranteed to be a `%Brando.Type.VideoConfig{}` — a plain-map cfg would
  miss the VideoConfig clause in `Brando.Upload.handle_upload_type/2` and fall
  into the generic image path.
  """
  def resolve_video_config(config_target),
    do: resolve_config(Brando.Videos, Brando.Type.VideoConfig, config_target)

  @doc """
  Resolve a file config target to `{cfg, resolved_target}`.

  Falls back to the default file config (and `"default"` target) when the
  target has no registered config. Note the resolved cfg may be a
  `%Brando.Type.VideoConfig{}` for `"video:"` targets (files wrapped by
  `:upload` videos resolve through the owning video asset's cfg).
  """
  def resolve_file_config(config_target),
    do: resolve_config(Brando.Files, Brando.Type.FileConfig, config_target)

  # Videos require the exact config struct (see resolve_video_config/1);
  # file targets may legitimately resolve to another cfg struct type.
  defp resolve_config(Brando.Videos = context, struct_mod, config_target) do
    resolved_target = normalize_config_target(config_target) || "default"

    case {valid_video_target_shape?(resolved_target), safe_get_config(context, resolved_target)} do
      {true, {:ok, cfg}} when is_struct(cfg, struct_mod) -> {cfg, resolved_target}
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
    case safe_get_config(context, "default") do
      {:ok, cfg} when is_struct(cfg, struct_mod) -> cfg
      _ -> struct_mod.default_config()
    end
  end

  # get_config_for raises on unknown target shapes — the upload manager must
  # never crash mid-consume over a config target, so treat any raise as
  # "unresolvable" and let the caller fall back to the default config.
  defp safe_get_config(context, resolved_target) do
    context.get_config_for(resolved_target)
  rescue
    _ -> :error
  end

  defp normalize_config_target(config_target) do
    Brando.Assets.ConfigTarget.serialize(config_target)
  rescue
    ArgumentError -> nil
  end

  defp valid_video_target_shape?("default"), do: true

  defp valid_video_target_shape?(target) do
    case String.split(target, ":") do
      [type, schema, field] when type in ["gallery", "video"] ->
        schema != "" and field != ""

      [type, schema, "function", function] when type in ["gallery", "video"] ->
        schema != "" and function != ""

      _ ->
        false
    end
  end
end
