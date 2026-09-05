defmodule Brando.Files.Replacement do
  @moduledoc "Replaces a library file's contents while preserving its identity and public URL."

  import Ecto.Query, only: [from: 2]

  alias Brando.Assets.CompletedCallback
  alias Brando.Files
  alias Brando.Tenant.Storage
  alias Brando.Uploads

  require Logger

  @doc "Validate a replacement against the stored file, before transferring bytes."
  def initiate(file_id, meta) do
    with {:ok, %{deleted_at: nil} = file} <- Files.get_file(file_id),
         {:ok, cfg} <- Files.get_config_for(file.config_target),
         :ok <- validate(file, cfg, meta) do
      # A replacement is staged on the server, including for CDN files. Never
      # presign a PUT to the live key: an interrupted upload must not replace it.
      {:ok, :server}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "The file is no longer available"}
    end
  rescue
    _ -> {:error, "The file's upload configuration is unavailable"}
  end

  @doc "Store a completed replacement. The original is retained on validation or storage failure."
  def store(file_id, %{path: path}, entry, user) do
    with {:ok, stat} <- File.stat(path) do
      meta = %{name: entry.client_name, size: stat.size, type: entry.client_type}
      schema = Brando.Files.File

      result =
        Brando.Repo.transaction(
          fn ->
            file = Brando.Repo.one(from f in schema, where: f.id == ^file_id and is_nil(f.deleted_at), lock: "FOR UPDATE")

            with %{id: _} <- file,
                 {:ok, cfg} <- Files.get_config_for(file.config_target),
                 :ok <- validate(file, cfg, meta),
                 {:ok, destination} <- destination(file, cfg),
                 {:ok, updated} <-
                   file |> Ecto.Changeset.change(filesize: stat.size, mime_type: meta.type) |> Brando.Repo.update(),
                 :ok <- store_contents(updated, cfg, path, destination) do
              {updated, cfg}
            else
              {:error, message} when is_binary(message) -> Brando.Repo.repo().rollback(message)
              nil -> Brando.Repo.repo().rollback("The file is no longer available")
              _ -> Brando.Repo.repo().rollback("Could not replace the file")
            end
          end,
          timeout: :infinity
        )

      case result do
        {:ok, {file, cfg}} ->
          Brando.Cache.Query.evict({:ok, file})
          CompletedCallback.run(cfg, file, user)
          {:ok, file}

        error ->
          error
      end
    else
      _ -> {:error, "Could not read the replacement file"}
    end
  rescue
    exception ->
      Logger.error("File replacement failed (#{inspect(exception.__struct__)})")
      {:error, "Could not replace the file"}
  end

  defp validate(file, cfg, %{name: name, size: size, type: mime_type}) do
    allowed = cfg.allowed_mimetypes

    with :ok <- Uploads.validate_intake(:file, name, size, cfg.size_limit) do
      cond do
        extension(name) != extension(file.filename) ->
          {:error, "Choose a file with the same extension (#{extension(file.filename)})"}

        allowed != ["*"] and mime_type not in allowed ->
          {:error, "Rejected file type [#{mime_type}]. Allowed: #{Enum.join(allowed, ", ")}"}

        true ->
          :ok
      end
    end
  end

  defp extension(name), do: name |> Path.extname() |> String.downcase()

  defp destination(file, cfg) do
    root = Path.expand(Storage.current_media_root())
    path = Path.expand(Path.join(cfg.upload_path, file.filename), root)

    if String.starts_with?(path, root <> "/"), do: {:ok, path}, else: {:error, "Invalid file storage path"}
  end

  defp store_contents(%{cdn: true} = file, cfg, source, destination) do
    cdn = cfg.cdn || Brando.CDN.config(Files)

    if cdn.enabled do
      key = Path.join(["media", cfg.upload_path, file.filename])
      opts = [content_type: file.mime_type] ++ Brando.CDN.build_content_disposition_opts(cfg, file.filename)
      opts = if cdn.direct_acl, do: Keyword.put(opts, :acl, cdn.direct_acl), else: opts
      s3_config = Brando.CDN.get_s3_config(%{cdn: cdn}, as: :keyword_list)

      case Brando.CDN.Client.impl().replace_file(cdn.bucket, key, source, opts, s3_config) do
        {:ok, _} ->
          # A CDN URL remains a CDN URL. Refresh a retained local copy only
          # after the object store has accepted the complete replacement.
          if cdn.keep_local_copy && store_local(source, destination) != :ok do
            Logger.warning("Replaced CDN file ##{file.id}, but could not refresh its local copy")
          end

          :ok

        {:error, _} ->
          {:error, "Could not replace the file on the CDN"}
      end
    else
      {:error, "The file's CDN configuration is unavailable"}
    end
  end

  defp store_contents(_file, _cfg, source, destination), do: store_local(source, destination)

  defp store_local(source, destination) do
    staged = destination <> ".replacement-" <> Ecto.UUID.generate()

    try do
      with :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(source, staged),
           :ok <- File.rename(staged, destination) do
        :ok
      else
        _ -> {:error, "Could not replace the stored file"}
      end
    after
      File.rm(staged)
    end
  end
end
