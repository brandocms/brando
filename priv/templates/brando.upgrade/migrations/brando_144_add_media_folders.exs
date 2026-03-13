defmodule Brando.Migrations.Media.AddMediaFolders do
  use Ecto.Migration

  def up do
    create table(:media_folders) do
      add :scope, :text, null: false
      add :name, :text, null: false
      add :path, :text, null: false
      add :parent_id, references(:media_folders, on_delete: :delete_all)
      timestamps()
    end

    create index(:media_folders, [:scope], name: :media_folders_scope_idx)
    create index(:media_folders, [:parent_id], name: :media_folders_parent_idx)
    create unique_index(:media_folders, [:scope, :path], name: :media_folders_scope_path_idx)

    create unique_index(:media_folders, [:scope, :parent_id, :name], name: :media_folders_scope_parent_name_idx)

    alter table(:images) do
      add :folder_id, references(:media_folders, on_delete: :nilify_all)
    end

    create index(:images, [:folder_id], name: :images_folder_id_idx)

    alter table(:files) do
      add :folder_id, references(:media_folders, on_delete: :nilify_all)
    end

    create index(:files, [:folder_id], name: :files_folder_id_idx)

    alter table(:videos) do
      add :folder_id, references(:media_folders, on_delete: :nilify_all)
    end

    create index(:videos, [:folder_id], name: :videos_folder_id_idx)

    flush()
    backfill_image_folders()
    backfill_file_folders()
    backfill_video_folders_from_files()
    backfill_video_folders_from_remote_ids()
  end

  def down do
    drop_if_exists index(:videos, [:folder_id], name: :videos_folder_id_idx)
    drop_if_exists index(:files, [:folder_id], name: :files_folder_id_idx)
    drop_if_exists index(:images, [:folder_id], name: :images_folder_id_idx)
    drop_if_exists index(:media_folders, [:scope, :parent_id, :name], name: :media_folders_scope_parent_name_idx)
    drop_if_exists index(:media_folders, [:scope, :path], name: :media_folders_scope_path_idx)
    drop_if_exists index(:media_folders, [:parent_id], name: :media_folders_parent_idx)
    drop_if_exists index(:media_folders, [:scope], name: :media_folders_scope_idx)

    alter table(:videos) do
      remove :folder_id
    end

    alter table(:files) do
      remove :folder_id
    end

    alter table(:images) do
      remove :folder_id
    end

    drop table(:media_folders)
  end

  defp backfill_image_folders do
    %{rows: rows} =
      repo().query!("""
      SELECT id, path, config_target
      FROM images
      WHERE folder_id IS NULL
        AND path IS NOT NULL
        AND path <> ''
      """)

    Enum.each(rows, fn [id, path, config_target] ->
      upload_root = image_upload_root(config_target)
      scope = "images"
      full_path = resolve_image_path(path, upload_root)

      with relative when is_binary(relative) <- relative_folder_for_path(full_path, scope),
           folder_id when is_integer(folder_id) <- ensure_folder(scope, relative) do
        repo().query!("UPDATE images SET folder_id = $1 WHERE id = $2 AND folder_id IS NULL", [folder_id, id])
      else
        _ -> :ok
      end
    end)
  end

  defp backfill_file_folders do
    %{rows: rows} =
      repo().query!("""
      SELECT id, filename, config_target
      FROM files
      WHERE folder_id IS NULL
        AND filename IS NOT NULL
        AND filename <> ''
      """)

    Enum.each(rows, fn [id, filename, config_target] ->
      full_path =
        filename
        |> normalize_path()
        |> resolve_file_path(config_target)

      upload_root = file_upload_root(config_target)

      with relative when is_binary(relative) <- relative_folder_for_path(full_path, upload_root),
           folder_id when is_integer(folder_id) <- ensure_folder(upload_root, relative) do
        repo().query!("UPDATE files SET folder_id = $1 WHERE id = $2 AND folder_id IS NULL", [folder_id, id])
      else
        _ -> :ok
      end
    end)
  end

  defp backfill_video_folders_from_files do
    repo().query!("""
    UPDATE videos v
    SET folder_id = f.folder_id
    FROM files f
    WHERE v.folder_id IS NULL
      AND v.file_id = f.id
      AND f.folder_id IS NOT NULL
    """)
  end

  defp backfill_video_folders_from_remote_ids do
    %{rows: rows} =
      repo().query!("""
      SELECT id, remote_id, config_target
      FROM videos
      WHERE folder_id IS NULL
        AND type = 'upload'
        AND remote_id IS NOT NULL
        AND remote_id <> ''
      """)

    Enum.each(rows, fn [id, remote_id, config_target] ->
      full_path =
        remote_id
        |> normalize_path()
        |> resolve_video_path(config_target)

      upload_root = video_upload_root(config_target)

      with relative when is_binary(relative) <- relative_folder_for_path(full_path, upload_root),
           folder_id when is_integer(folder_id) <- ensure_folder(upload_root, relative) do
        repo().query!("UPDATE videos SET folder_id = $1 WHERE id = $2 AND folder_id IS NULL", [folder_id, id])
      else
        _ -> :ok
      end
    end)
  end

  defp ensure_folder(scope, path) when is_binary(scope) and is_binary(path) do
    scope = normalize_path(scope)
    path = normalize_path(path)

    if path in ["", "."] do
      nil
    else
      do_ensure_folder(scope, path)
    end
  end

  defp ensure_folder(_scope, _path), do: nil

  defp do_ensure_folder(scope, path) do
    path
    |> String.split("/", trim: true)
    |> Enum.reduce_while({nil, ""}, fn segment, {parent_id, parent_path} ->
      current_path =
        case parent_path do
          "" -> segment
          _ -> parent_path <> "/" <> segment
        end

      case fetch_folder_id(scope, current_path) do
        id when is_integer(id) ->
          {:cont, {id, current_path}}

        nil ->
          name = segment

          repo().query!(
            """
            INSERT INTO media_folders (scope, name, path, parent_id, inserted_at, updated_at)
            VALUES ($1, $2, $3, $4, NOW(), NOW())
            ON CONFLICT (scope, path) DO NOTHING
            """,
            [scope, name, current_path, parent_id]
          )

          case fetch_folder_id(scope, current_path) do
            id when is_integer(id) -> {:cont, {id, current_path}}
            _ -> {:halt, :error}
          end
      end
    end)
    |> case do
      {folder_id, _} when is_integer(folder_id) -> folder_id
      _ -> nil
    end
  end

  defp fetch_folder_id(scope, path) do
    case repo().query!(
           "SELECT id FROM media_folders WHERE scope = $1 AND path = $2 LIMIT 1",
           [scope, path]
         ) do
      %{rows: [[id]]} -> id
      _ -> nil
    end
  end

  defp normalize_path(path) when is_binary(path) do
    path
    |> String.replace("\\", "/")
    |> String.trim()
    |> String.trim("/")
  end

  defp normalize_path(_), do: ""

  defp resolve_image_path(path, upload_root) do
    normalized_path = normalize_path(path)
    scope = "images"
    absolute_upload_root = absolute_upload_root(upload_root, scope)
    upload_root_relative = strip_scope_prefix(absolute_upload_root, scope)

    cond do
      normalized_path in ["", "."] ->
        ""

      absolute_media_path?(normalized_path) ->
        normalized_path

      upload_root_relative != "" and
          (normalized_path == upload_root_relative or
             String.starts_with?(normalized_path, upload_root_relative <> "/")) ->
        Path.join(scope, normalized_path) |> normalize_path()

      String.contains?(normalized_path, "/") ->
        Path.join(scope, normalized_path) |> normalize_path()

      true ->
        Path.join(absolute_upload_root, normalized_path) |> normalize_path()
    end
  end

  defp absolute_upload_root(upload_root, scope) do
    normalized_upload_root = normalize_path(upload_root)
    normalized_scope = normalize_path(scope)

    cond do
      normalized_upload_root in ["", "."] ->
        normalized_scope

      normalized_upload_root == normalized_scope ->
        normalized_scope

      String.starts_with?(normalized_upload_root, normalized_scope <> "/") ->
        normalized_upload_root

      true ->
        Path.join(normalized_scope, normalized_upload_root) |> normalize_path()
    end
  end

  defp strip_scope_prefix(path, scope) do
    normalized_path = normalize_path(path)
    normalized_scope = normalize_path(scope)

    cond do
      normalized_path == normalized_scope ->
        ""

      String.starts_with?(normalized_path, normalized_scope <> "/") ->
        String.replace_prefix(normalized_path, normalized_scope <> "/", "")

      true ->
        normalized_path
    end
  end

  defp resolve_file_path(filename, config_target) do
    if absolute_media_path?(filename) do
      filename
    else
      upload_root = file_upload_root(config_target)

      case upload_root do
        nil -> filename
        root -> Path.join(root, filename)
      end
    end
  end

  defp resolve_video_path(remote_id, config_target) do
    if absolute_media_path?(remote_id) do
      remote_id
    else
      upload_root = video_upload_root(config_target)

      case upload_root do
        nil -> remote_id
        root -> Path.join(root, remote_id)
      end
    end
  end

  defp relative_folder_for_path(path, upload_root) do
    normalized_path = normalize_path(path)
    normalized_root = normalize_path(upload_root)
    directory = Path.dirname(normalized_path)

    cond do
      directory in ["", "."] ->
        nil

      normalized_root in ["", "."] ->
        directory

      directory == normalized_root ->
        nil

      String.starts_with?(directory, normalized_root <> "/") ->
        String.replace_prefix(directory, normalized_root <> "/", "")

      true ->
        nil
    end
  end

  defp absolute_media_path?(path) when is_binary(path) do
    Enum.any?(["images/", "files/", "videos/"], &String.starts_with?(path, &1))
  end

  defp absolute_media_path?(_), do: false

  defp image_upload_root(config_target) do
    try do
      case Brando.Images.get_config_for(%{config_target: normalize_config_target(config_target, "default")}) do
        {:ok, %{upload_path: upload_path}} -> normalize_path(upload_path)
        _ -> "images/default"
      end
    rescue
      _ -> "images/default"
    end
  end

  defp file_upload_root(config_target) do
    try do
      case Brando.Files.get_config_for(%{config_target: normalize_config_target(config_target, "default")}) do
        {:ok, %{upload_path: upload_path}} -> normalize_path(upload_path)
        _ -> "files/default"
      end
    rescue
      _ -> "files/default"
    end
  end

  defp video_upload_root(config_target) do
    try do
      case Brando.Videos.get_config_for(%{config_target: normalize_config_target(config_target, "default")}) do
        {:ok, %{upload_path: upload_path}} -> normalize_path(upload_path)
        _ -> "videos/default"
      end
    rescue
      _ -> "videos/default"
    end
  end

  defp normalize_config_target(config_target, fallback)
       when is_binary(config_target) and config_target != "",
       do: config_target

  defp normalize_config_target(_, fallback), do: fallback
end
