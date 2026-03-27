defmodule Brando.Migrations.Media.BackfillVideoFolders do
  use Ecto.Migration

  def up do
    backfill_video_folders()
  end

  def down do
    repo().query!("UPDATE videos SET folder_id = NULL WHERE folder_id IS NOT NULL")
  end

  defp backfill_video_folders do
    %{rows: rows} =
      repo().query!("""
      SELECT id, config_target
      FROM videos
      WHERE folder_id IS NULL
      """)

    Enum.each(rows, fn [id, config_target] ->
      upload_root = video_upload_root(config_target)
      {scope, path} = scope_and_path(upload_root)
      folder_id = ensure_folder(scope, path)

      if folder_id do
        repo().query!(
          "UPDATE videos SET folder_id = $1 WHERE id = $2 AND folder_id IS NULL",
          [folder_id, id]
        )
      end
    end)
  end

  # Split upload_root "videos/default" into scope "videos" and path "default"
  # to match how images use scope "images" and path "site/default"
  defp scope_and_path(upload_root) do
    case String.split(upload_root, "/", parts: 2) do
      [scope, path] -> {scope, path}
      [single] -> {single, single}
    end
  end

  defp ensure_folder(scope, path) do
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
          repo().query!(
            """
            INSERT INTO media_folders (scope, name, path, parent_id, inserted_at, updated_at)
            VALUES ($1, $2, $3, $4, NOW(), NOW())
            ON CONFLICT (scope, path) DO NOTHING
            """,
            [scope, segment, current_path, parent_id]
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

  defp video_upload_root(config_target) do
    try do
      resolved =
        if is_binary(config_target) and config_target != "",
          do: config_target,
          else: "default"

      case Brando.Videos.get_config_for(%{config_target: resolved}) do
        {:ok, %{upload_path: upload_path}} -> normalize_path(upload_path)
        _ -> "videos/default"
      end
    rescue
      _ -> "videos/default"
    end
  end

  defp normalize_path(path) when is_binary(path) do
    path
    |> String.replace("\\", "/")
    |> String.trim()
    |> String.trim("/")
  end

  defp normalize_path(_), do: "videos/default"
end
