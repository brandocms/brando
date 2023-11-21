defmodule Mix.Tasks.Brando.Static.Deploy do
  use Mix.Task
  alias ExAws.S3

  @shortdoc "Upload static files to CDN"

  def run(args) do
    {parsed_opts, _, _} = OptionParser.parse(args, switches: [purge: :boolean])
    Mix.Task.run("app.config")

    unless Brando.CDN.enabled?(Brando.Static) do
      raise "CDN not enabled in config."
    end

    :erlang.system_flag(:backtrace_depth, 20)

    Application.ensure_all_started(:ex_aws)
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:sweet_xml)

    Mix.shell().info("=> Preparing bucket")

    s3_config =
      Brando.Static
      |> Brando.CDN.config(:s3)
      |> Map.from_struct()
      |> Map.to_list()

    require Logger
    Logger.error(inspect(s3_config, pretty: true))

    bucket = Brando.CDN.config(Brando.Static, :bucket)

    bucket
    |> S3.get_bucket_location()
    |> ExAws.request(s3_config)
    |> case do
      {:ok, _result} ->
        Mix.shell().info("==> OK - bucket [#{bucket}] exists")

      {:error, _err} ->
        Mix.shell().error("==> ERROR - bucket [#{bucket}] missing")
        Mix.shell().info("==> Creating bucket ...")

        bucket
        |> ExAws.S3.put_bucket(s3_config.region)
        |> ExAws.request(s3_config)
    end

    require Logger

    if parsed_opts[:purge] == true do
      stream =
        ExAws.S3.list_objects(bucket, prefix: "static/")
        |> ExAws.stream!(s3_config)
        |> Stream.map(& &1.key)

      bucket
      |> ExAws.S3.delete_all_objects(stream)
      |> ExAws.request(s3_config)
    end

    static_dir = "priv/static"

    static_dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&(File.dir?(&1) == false))
    |> Enum.each(fn f ->
      IO.puts("==> Uploading -> #{f}")

      bucket
      |> S3.put_object(String.replace(f, "priv", ""), File.read!(f),
        acl: :public_read,
        content_type: MIME.from_path(f)
      )
      |> ExAws.request!(s3_config)
    end)

    Mix.shell().info("==> Static files uploaded")
  end
end
