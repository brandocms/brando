defmodule Mix.Tasks.Brando.Files.UpdateContentDisposition do
  use Mix.Task
  alias ExAws.S3

  @shortdoc "Update Content-Disposition header on existing CDN files"

  @moduledoc """
  Update Content-Disposition header on existing CDN files.

  This task uses S3's copy-in-place feature to update metadata without
  re-uploading the file content.

  ## Usage

      # Update all files for a specific config_target
      mix brando.files.update_content_disposition "file:MyApp.MySchema:pdf_file"

      # Update with specific disposition (inline or attachment)
      mix brando.files.update_content_disposition "file:MyApp.MySchema:pdf_file" --disposition inline

      # Dry run (show what would be updated)
      mix brando.files.update_content_disposition "file:MyApp.MySchema:pdf_file" --dry-run

  ## Options

    * `--disposition` - The disposition value: "inline" or "attachment" (default: from config)
    * `--dry-run` - Show what would be updated without making changes

  """

  @spec run(any) :: no_return
  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        switches: [disposition: :string, dry_run: :boolean],
        aliases: [d: :disposition, n: :dry_run]
      )

    config_target =
      case rest do
        [target] -> target
        _ -> Mix.raise("Usage: mix brando.files.update_content_disposition \"file:MyApp.Schema:field\"")
      end

    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    {:ok, config} = Brando.Files.get_config_for(config_target)

    disposition =
      case opts[:disposition] do
        nil -> Map.get(config, :content_disposition)
        "inline" -> :inline
        "attachment" -> :attachment
        other -> Mix.raise("Invalid disposition: #{other}. Use 'inline' or 'attachment'")
      end

    if is_nil(disposition) do
      Mix.raise("""
      No content_disposition configured for #{config_target} and none specified via --disposition.

      Either add `content_disposition: :inline` to your FileConfig, or use:
        mix brando.files.update_content_disposition "#{config_target}" --disposition inline
      """)
    end

    dry_run? = opts[:dry_run] == true

    Mix.shell().info("""

    ======================================
    Brando Files - Update Content-Disposition
    ======================================
    Config target: #{config_target}
    Disposition: #{disposition}
    Dry run: #{dry_run?}
    """)

    s3_config =
      Brando.Files
      |> Brando.CDN.config(:s3)
      |> Map.from_struct()
      |> Map.to_list()

    bucket = Brando.CDN.config(Brando.Files, :bucket)

    import Ecto.Query

    files =
      from(f in Brando.Files.File,
        where: f.config_target == ^config_target and f.cdn == true,
        select: f
      )
      |> Brando.Repo.all()

    Mix.shell().info("Found #{length(files)} files to update\n")

    if length(files) == 0 do
      Mix.shell().info("No files to update.")
    else
      for file <- files do
        s3_key = Path.join(["media", config.upload_path, file.filename])

        disposition_value =
          case disposition do
            :inline -> "inline"
            :attachment -> "attachment; filename=\"#{file.filename}\""
          end

        Mix.shell().info("  Updating: #{s3_key}")
        Mix.shell().info("    -> Content-Disposition: #{disposition_value}")

        unless dry_run? do
          bucket
          |> S3.put_object_copy(s3_key, bucket, s3_key,
            metadata_directive: :REPLACE,
            content_disposition: disposition_value,
            content_type: file.mime_type,
            acl: :public_read
          )
          |> ExAws.request(s3_config)
          |> case do
            {:ok, _} ->
              Mix.shell().info([:green, "    [OK]\n"])

            {:error, err} ->
              Mix.shell().error("    [ERROR] #{inspect(err)}\n")
          end
        end
      end

      Mix.shell().info("\nDone!")
    end
  end
end
