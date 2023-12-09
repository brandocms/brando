defmodule Brando.CDN do
  @moduledoc """
  Interfacing with Content Delivery Networks

  ## Configure

  Setting the `s3` config key to `:default` will use the s3 config
  setting from `Brando.CDN.S3Config`

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

  """
  require Logger
  import Ecto.Query
  import Brando.Gettext
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
    s3_config =
      Brando.Images
      |> config(:s3)

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
    args = %{
      file_id: file.id,
      config_target: file.config_target,
      user_id: user.id,
      field_full_path: field_full_path
    }

    Brando.repo().delete_all(
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
    Brando.repo().delete_all(
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

    case s3_upload(s3_bucket, original_key, dest_key, s3_config, user_id) do
      {:ok, s3_key} ->
        {:ok, s3_key}

      {:error, {:http_error, 403, err}} ->
        Logger.error("==> Error uploading file. 403 from AMAZON")
        Logger.error(inspect(err, pretty: true))
        {:error, "S3 Upload failed"}
    end
  end

  defp get_bucket_for_image_config(%{cdn: %{bucket: bucket}}), do: bucket
  defp get_bucket_for_image_config(_), do: config(Brando.Images, :bucket)

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

    if !s3_bucket do
      raise """

      upload_image -- missing s3_bucket for config

      #{inspect(s3_config, pretty: true)}
      """
    end

    progress_string =
      gettext(
        "Uploading image to CDN &rarr; %{s3_bucket}",
        src_key: src_key,
        s3_bucket: s3_bucket
      )

    BrandoAdmin.Progress.update(%Brando.Users.User{id: user_id}, progress_string, %{
      key: src_key,
      percent: 0,
      filename: src_key
    })

    s3_upload(s3_bucket, src_key, dest_key, s3_config, user_id)
  end

  defp s3_upload(s3_bucket, src_key, s3_dest_key, s3_config, user_id) do
    src_key
    |> Upload.stream_file()
    |> S3.upload(s3_bucket, s3_dest_key, acl: :public_read)
    |> ExAws.request(s3_config)
    |> case do
      {:ok, %{status_code: 200}} ->
        progress_string =
          gettext(
            "Uploading image to CDN &rarr; %{s3_bucket}",
            src_key: src_key,
            s3_bucket: s3_bucket
          )

        BrandoAdmin.Progress.update(%Brando.Users.User{id: user_id}, progress_string, %{
          key: src_key,
          percent: 100,
          filename: src_key
        })

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
      |> Map.to_list()

    bucket
    |> S3.get_bucket_location()
    |> ExAws.request(s3_config)
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

  def key_exists?(object_key, field_cfg) do
    s3_config = get_s3_config(field_cfg, as: :keyword_list)
    cdn_config = Map.get(field_cfg, :cdn)
    bucket = cdn_config.bucket

    bucket
    |> ExAws.S3.head_object(object_key)
    |> ExAws.request(s3_config)
    |> case do
      {:ok, _} -> true
      _ -> false
    end
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
end
