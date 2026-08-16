defmodule Brando.CDN do
  @moduledoc """
  Interfacing with Content Delivery Networks

  ## Configure

  Setting the `s3` config key to `:default` will use the s3 config
  setting from `Brando.CDN.S3Config`.

  Example configuration (in runtime.exs):

  ```elixir
  config :brando, Brando.CDN.S3Config, %Brando.CDN.S3Config{
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      scheme: "https://",
      host: "ams3.digitaloceanspaces.com",
      region: "ams3"
    }

  config :brando, Brando.Files,
    cdn: %Brando.CDN.Config{
      enabled: false,
      media_url:
        System.get_env("BRANDO_CDN_FILES_MEDIA_URL") ||
          "https://mybucket.ams3.digitaloceanspaces.com",
      bucket: System.get_env("BRANDO_CDN_FILES_BUCKET"),
      s3: :default
    }

  config :brando, Brando.Static,
    cdn: %Brando.CDN.Config{
      enabled: false,
      media_url:
        System.get_env("BRANDO_CDN_FILES_MEDIA_URL") ||
          "https://mybucket.ams3.digitaloceanspaces.com",
      bucket: System.get_env("BRANDO_CDN_FILES_BUCKET"),
      s3: :default
    }

  config :brando, Brando.Images,
    cdn: %Brando.CDN.Config{
      enabled: false,
      media_url:
        System.get_env("BRANDO_CDN_FILES_MEDIA_URL") ||
          "https://mybucket.ams3.digitaloceanspaces.com",
      bucket: System.get_env("BRANDO_CDN_FILES_BUCKET"),
      s3: :default
    }

  ```

  """
  require Logger
  import Ecto.Query
  use Gettext, backend: Brando.Gettext
  alias Brando.Worker
  alias ExAws.S3
  alias ExAws.S3.Upload

  @type changeset :: Ecto.Changeset.t()
  @type upload_error :: {:error, {:cdn, {:upload, :failed}}}

  def config(module) do
    Brando.config(module, :cdn) || %Brando.CDN.Config{}
  end

  def config(module, :s3) do
    s3_cfg =
      module
      |> config()
      |> Map.get(:s3, nil)

    if s3_cfg == :default do
      Brando.config(Brando.CDN.S3Config) ||
        raise "Missing default Brando.CDN.S3Config, and CDN config referenced `s3: :default`. Either insert a custom config under the `s3` key, or set `Brando.CDN.S3Config`. See `Brando.CDN` moduledocs for more info"
    else
      s3_cfg
    end
  end

  def config(module, key) do
    module
    |> config()
    |> Map.get(key, nil)
  end

  def get_s3_config(%{cdn: %{enabled: true, s3: :default}}, as: type) do
    s3_config = Brando.config(Brando.CDN.S3Config)

    if !s3_config do
      raise "Missing default Brando.CDN.S3Config, and CDN config referenced `s3: :default`. Either insert a custom config under the `s3` key, or set `Brando.CDN.S3Config`. See `Brando.CDN` moduledocs for more info"
    end

    if type == :keyword_list do
      s3_config
      |> Map.from_struct()
      |> Map.to_list()
    else
      s3_config
    end
  end

  def get_s3_config(%{cdn: %{enabled: true, s3: s3_config}}, as: type) do
    if type == :keyword_list do
      s3_config
      |> Map.from_struct()
      |> Map.to_list()
    else
      s3_config
    end
  end

  def get_s3_config(_, as: type) do
    s3_config = config(Brando.Images, :s3)

    # The field config carries no `:cdn`, so this is the fallback — and it is
    # allowed to be missing, which makes `s3_config` `nil`. `Map.from_struct/1`
    # accepts an atom as a module and would take that clause (deprecated since
    # Elixir 1.20), warn, and then fail on `nil.__struct__/0` — a message that
    # says nothing about the config that is actually absent. Same shape as the
    # `s3: :default` clause above.
    #
    # The subject changes between the paragraph above and this one, which is
    # the easiest thing to misread here. What lands us in *this clause* is the
    # **field** config having no `:cdn`. What decides whether we **raise** is
    # a different config entirely: `Brando.Images`'. Reaching the raise needs
    # that one to be present and to carry an explicit `s3: nil`, because
    # `%Brando.CDN.Config{}` defaults `:s3` to a populated
    # `%Brando.CDN.S3Config{}` — so an app with no CDN configured anywhere
    # falls through here and *succeeds*, handing back nil credentials rather
    # than raising. See `key_available?/2`, which is where that matters.
    #
    # Deliberately `!s3_config` and not a wider guard. A **keyword-list** config
    # cannot arrive here: given `cdn: [enabled: true, s3: …]`, `config/2` above
    # calls `Map.get/3` on that list and raises `BadMapError` at `:72`, long
    # before this clause. (`Brando.Uploads`' `normalize_cdn_config/1` does accept
    # a keyword-list CDN config, but it `struct/2`s it into a `%Config{}` first
    # and is a different entry point.) The shape that *does* slip past this
    # guard is a keyword-list `:s3` **sub**-config, which then fails on
    # `Map.from_struct/1` below — and equally at `:107` in the clause above,
    # which has no guard at all. Nothing in this repo, its docs or its tests
    # writes that shape; every one uses `%S3Config{}` or `:default`. Guarding it
    # in one of the two clauses would buy a better message on a config nobody
    # writes, while leaving the other clause to raise the old one.
    if !s3_config do
      raise "Missing S3 config. The field config has no `:cdn`, and there is no fallback `s3` config under `Brando.Images`. Either give the field its own `:cdn` config, or set one under `Brando.Images`. See `Brando.CDN` moduledocs for more info"
    end

    if type == :keyword_list do
      s3_config
      |> Map.from_struct()
      |> Map.to_list()
    else
      s3_config
    end
  end

  def get_prefix(%{cdn: %{media_url: media_url}}), do: media_url
  def get_prefix(module), do: config(module, :media_url)

  def queue_upload(file_or_image, user, field_full_path \\ [])

  def queue_upload(%Brando.Files.File{} = file, user, field_full_path) do
    args =
      Brando.Tenant.Job.attach(%{
        file_id: file.id,
        config_target: file.config_target,
        user_id: user.id,
        field_full_path: field_full_path
      })

    Brando.Repo.delete_all(
      from j in Oban.Job,
        where: fragment("? @> ?", j.args, ^args)
    )

    args
    |> Worker.FileUploader.new(replace_args: true)
    |> Oban.insert()
  end

  def queue_upload(%Brando.Images.Image{} = image, user, field_full_path) do
    src_key = Path.join(["media", image.path])
    dest_key = src_key

    args = %{
      src_key: src_key,
      dest_key: dest_key,
      image_id: image.id,
      config_target: image.config_target,
      user_id: user.id,
      field_full_path: field_full_path
    }

    create_image_upload_job(args)

    # upload individual sizes from sizes map
    for {_, path} <- image.sizes do
      sized_key = Path.join(["media", path])
      dest_key = sized_key

      args = %{
        src_key: sized_key,
        dest_key: dest_key,
        image_id: image.id,
        config_target: image.config_target,
        user_id: user.id,
        field_full_path: field_full_path
      }

      create_image_upload_job(args)
    end
  end

  defp create_image_upload_job(args) do
    args = Brando.Tenant.Job.attach(args)

    Brando.Repo.delete_all(
      from j in Oban.Job,
        where: fragment("? @> ?", j.args, ^args)
    )

    args
    |> Worker.ImageUploader.new(replace_args: true, tags: ["image_upload_#{args.image_id}"])
    |> Oban.insert()
  end

  @doc """

  """
  @spec upload_file(map, map, any) :: {:ok, binary} | {:error, binary}
  def upload_file(%Brando.Files.File{} = file, config, user_id) do
    s3_bucket = config(Brando.Files, :bucket)
    cdn_config = config.cdn || config(Brando.Files)

    # upload original
    local_path = config.upload_path
    filename = file.filename
    original_key = Path.join(["media", local_path, filename])
    dest_key = original_key

    s3_config =
      Brando.Files
      |> Brando.CDN.config(:s3)
      |> Map.from_struct()
      |> Map.to_list()

    upload_opts = build_content_disposition_opts(config, filename)

    case s3_upload(s3_bucket, original_key, dest_key, s3_config, user_id, nil, upload_opts) do
      {:ok, s3_key} ->
        if cdn_config.keep_local_copy == false do
          local_path_and_filename = Path.join([local_path, filename])
          original_path = Brando.Images.Utils.media_path(local_path_and_filename)
          File.rm!(original_path)
        end

        {:ok, s3_key}

      {:error, {:http_error, 403, err}} ->
        Logger.error("==> Error uploading file. 403 from AMAZON")
        Logger.error(inspect(err, pretty: true))
        {:error, "S3 Upload failed"}
    end
  end

  defp get_bucket_for_image_config(%{cdn: %{bucket: bucket}}), do: bucket
  defp get_bucket_for_image_config(_), do: config(Brando.Images, :bucket)

  def maybe_upload_file(file, field_full_path, user, %{cdn: %{enabled: true}}) do
    queue_upload(file, user, field_full_path)
  end

  def maybe_upload_file(file, field_full_path, user, _) do
    if Brando.CDN.enabled?(Brando.Files) do
      queue_upload(file, user, field_full_path)
    else
      {:ok, :no_job}
    end
  end

  def maybe_upload_image(image, field_full_path, user, %{cdn: %{enabled: true}}) do
    queue_upload(image, user, field_full_path)
  end

  def maybe_upload_image(image, field_full_path, user, _) do
    if Brando.CDN.enabled?(Brando.Images) do
      queue_upload(image, user, field_full_path)
    else
      {:ok, :no_job}
    end
  end

  def upload_image(src_key, dest_key, config, user_id) do
    s3_bucket = get_bucket_for_image_config(config)
    s3_config = get_s3_config(config, as: :keyword_list)
    cdn_config = config.cdn || config(Brando.Images)

    if !s3_bucket do
      # Credentials are dropped rather than inspected. `get_s3_config/2` with
      # `as: :keyword_list` hands back `%S3Config{}` through `Map.from_struct/1`,
      # so `:access_key_id` and `:secret_access_key` are plain values in this
      # list — and a raise message is not a private place. It reaches the
      # Logger, Oban's `errors` column and any attached error reporter.
      #
      # `@derive Inspect` on `%S3Config{}` does not cover this: by here the
      # struct is already a keyword list, and derivation only applies to the
      # struct. It is set on the struct too, for the paths that do inspect one.
      raise """

      upload_image -- missing s3_bucket for config

      #{inspect(Keyword.drop(s3_config, [:access_key_id, :secret_access_key]), pretty: true)}

      (S3 credentials omitted.)
      """
    end

    progress_string =
      gettext(
        "Uploading image to CDN &rarr; %{s3_bucket}",
        src_key: src_key,
        s3_bucket: s3_bucket
      )

    progress_key = Brando.Utils.generate_uid()

    BrandoAdmin.Progress.update(user_id, progress_string, %{
      key: progress_key,
      percent: 0,
      filename: src_key
    })

    case s3_upload(s3_bucket, src_key, dest_key, s3_config, user_id, progress_key) do
      {:ok, s3_key} ->
        if cdn_config.keep_local_copy == false do
          # local_path_and_filename = Path.join([local_path, filename])
          # original_path = Brando.Images.Utils.media_path(local_path_and_filename)
          File.rm!(src_key)
        end

        {:ok, s3_key}

      {:error, {:http_error, 403, err}} ->
        Logger.error("==> Error uploading file. 403 from AMAZON")
        Logger.error(inspect(err, pretty: true))
        {:error, "S3 Upload failed"}
    end
  end

  defp s3_upload(s3_bucket, src_key, s3_dest_key, s3_config, user_id, progress_key, opts \\ []) do
    upload_opts = Keyword.merge([acl: :public_read], opts)

    src_key
    |> Upload.stream_file()
    |> S3.upload(s3_bucket, s3_dest_key, upload_opts)
    |> ExAws.request(s3_config)
    |> case do
      {:ok, %{status_code: 200}} ->
        progress_string =
          gettext(
            "Uploading image to CDN &rarr; %{s3_bucket}",
            src_key: src_key,
            s3_bucket: s3_bucket
          )

        if progress_key do
          BrandoAdmin.Progress.update(user_id, progress_string, %{
            key: progress_key,
            percent: 100,
            filename: src_key
          })
        end

        {:ok, s3_dest_key}

      {:error, error} ->
        {:error, error}
    end
  rescue
    e in ExAws.Error ->
      Logger.error(inspect(e))
      Logger.error(e.message)
      {:error, :invalid_bucket}
  end

  @spec ensure_bucket_exists(module) :: {:ok, {:bucket, :exists}}
  def ensure_bucket_exists(module) do
    bucket = config(module, :bucket)

    s3_config =
      module
      |> config(:s3)
      |> Map.from_struct()

    s3_config_list = Map.to_list(s3_config)

    bucket
    |> S3.get_bucket_location()
    |> ExAws.request(s3_config_list)
    |> case do
      {:ok, _result} ->
        :ok

      {:error, _err} ->
        bucket
        |> ExAws.S3.put_bucket(s3_config.region)
        |> ExAws.request()
        |> case do
          {:ok, _} ->
            :ok

          {:error, err} ->
            raise """

            ==> Bucket #{bucket} not found!"

            #{inspect(err, pretty: true)}

            """
        end
    end

    {:ok, {:bucket, :exists}}
  end

  @doc """
  Whether `object_key` is free to write to.

  Only a definitive `{:error, :not_found}` frees the key. A hit, or an error we
  cannot interpret — a 403 from a bucket that masks 404 without `s3:ListBucket`,
  a timeout, a signature failure — reads as **occupied**, because the caller
  uses a `true` here to justify writing to that key. Guessing "free" overwrites
  a live asset's bytes underneath its existing row; guessing "taken" costs one
  unnecessary `unique_filename/1` suffix. Nothing is blocked either way.

  This is expressible only because `Brando.CDN.Client.ExAws` maps 404 — and
  nothing else — to `:not_found`. It therefore reduces to: does the configured
  provider 404 on an absent key? DigitalOcean Spaces does. A provider that
  answers some other way gets a suffix on every upload — functional, but the
  collision-avoidance name appears where it need not.

  One outcome is not on that scale: a `field_cfg` with no `:cdn` **raises**
  rather than returning either answer. `head_object/2` needs both an S3 config
  and a bucket, and with `:cdn` absent it is the **bucket** that fails — not
  the S3 config, which is the intuitive answer and the wrong one.

  Measured rather than read: `get_s3_config/2` falls through to the
  `Brando.Images` `:s3` fallback, and because `%Brando.CDN.Config{}` defaults
  `:s3` to a populated `%Brando.CDN.S3Config{}`, that fallback ordinarily
  **succeeds**, handing back a keyword list whose credentials are `nil`. The
  raise arrives just after it, in `head_object/2`, on `cdn_config.bucket`:
  `Map.get(field_cfg, :cdn)` returned `nil`, and the dot on `nil` raises
  `BadMapError` — *not* `UndefinedFunctionError`, which is what a literal
  `nil.bucket` would give; this is a variable, so it takes the map path.

  Cited by function rather than by line, per the standard the audit arrived at:
  every interior line number this file has carried has been wrong at least
  once, including one written into this paragraph that pointed inside this
  docstring.

  The config error `get_s3_config/2` raises is the narrower case: it needs
  `:cdn` to be present *and* to carry an explicit `s3: nil`. Either way nothing
  reaches the network, so callers on a possibly-CDN-less config must still
  check first — which is the part that matters here, and it is unchanged.
  """
  def key_available?(object_key, field_cfg) do
    head_object(object_key, field_cfg) == {:error, :not_found}
  end

  @doc """
  Fetch object metadata from the configured S3-compatible bucket.

  The raw ExAws response is returned so callers can validate headers such as
  `content-length` and `content-type` before trusting a client-side completion
  signal.
  """
  def head_object(object_key, field_cfg) do
    s3_config = get_s3_config(field_cfg, as: :keyword_list)
    cdn_config = Map.get(field_cfg, :cdn)
    bucket = cdn_config.bucket

    Brando.CDN.Client.impl().head_object(bucket, object_key, s3_config)
  end

  @doc """
  Delete an object from the field's bucket.

  Used to reap the objects of client-direct uploads that never finalized
  (`Brando.Worker.UploadIntentReaper`) — those have no asset row, so no
  row-driven cleanup path can ever reach them.

  S3 `DELETE` is idempotent: removing a key that was never written succeeds.
  """
  def delete_object(object_key, field_cfg) do
    s3_config = get_s3_config(field_cfg, as: :keyword_list)
    cdn_config = Map.get(field_cfg, :cdn)
    bucket = cdn_config.bucket

    Brando.CDN.Client.impl().delete_object(bucket, object_key, s3_config)
  end

  @doc """
  Check if we use CDN for the module
  """
  @spec enabled?(module) :: boolean
  def enabled?(module) when is_atom(module) do
    cdn_config = Brando.config(module, :cdn) || %{}
    !!Map.get(cdn_config, :enabled, false)
  rescue
    _ -> false
  end

  @doc """
  Builds Content-Disposition header value from config.

  Returns keyword list with :content_disposition key if configured, empty list otherwise.
  """
  def build_content_disposition_opts(config, filename) do
    case Map.get(config, :content_disposition) do
      nil -> []
      :inline -> [content_disposition: "inline"]
      :attachment -> [content_disposition: "attachment; filename=\"#{filename}\""]
    end
  end
end
