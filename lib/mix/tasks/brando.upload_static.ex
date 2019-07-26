defmodule Mix.Tasks.Brando.UploadStatic do
  use Mix.Task
  alias ExAws.S3

  @shortdoc "Upload static files to CDN"

  def run(_args) do
    :erlang.system_flag(:backtrace_depth, 20)

    Application.ensure_all_started(:ex_aws)
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:sweet_xml)

    Mix.shell().info("=> Preparing bucket")

    bucket = Atom.to_string(Brando.otp_app())

    require Logger

    bucket
    |> S3.get_bucket_location()
    |> ExAws.request()
    |> case do
      {:ok, _result} ->
        Mix.shell().info("==> OK - bucket [#{bucket}] exists")

      {:error, _err} ->
        Mix.shell().error("==> ERROR - bucket [#{bucket}] missing")
        Mix.shell().info("==> Creating bucket ...")

        bucket
        |> ExAws.S3.put_bucket("fra1")
        |> ExAws.request()
    end

    static_dir = "priv/static"

    static_dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&(String.contains?(&1, "hot-update.js") == false))
    |> Enum.filter(&(File.dir?(&1) == false))
    |> Enum.each(fn f ->
      IO.puts("==> Uploading -> #{f}")

      bucket
      |> S3.put_object(String.replace(f, "priv", ""), File.read!(f),
        acl: :public_read,
        content_type: MIME.from_path(f)
      )
      |> ExAws.request!()
    end)

    Mix.shell().info("==> Static files uploaded")
  end
end
