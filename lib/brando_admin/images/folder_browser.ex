defmodule BrandoAdmin.Images.FolderBrowser do
  @moduledoc false

  import Ecto.Query

  alias Brando.Images
  alias Brando.Media.Folder
  alias Brando.Repo

  @max_recent_folders 5
  @default_scope "images"

  def upload_root(config_target) do
    resolved_target =
      config_target
      |> normalize_config_target()
      |> Kernel.||("default")

    case Images.get_config_for(%{config_target: resolved_target}) do
      {:ok, %{upload_path: upload_path}} -> normalize_folder(upload_path)
      _ -> normalize_folder("images/default")
    end
  end

  def normalize_folder(nil), do: nil

  def normalize_folder(folder) when is_binary(folder) do
    folder
    |> String.trim()
    |> String.replace("\\", "/")
    |> String.split("/", trim: true)
    |> Enum.reject(&(&1 in [".", ".."]))
    |> Enum.join("/")
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  def scope_for(upload_root), do: normalize_folder(upload_root) || @default_scope

  def absolute_folder(nil, upload_root), do: normalize_folder(upload_root)
  def absolute_folder("", upload_root), do: normalize_folder(upload_root)

  def absolute_folder(folder, upload_root) do
    normalized_root = normalize_folder(upload_root)
    normalized_folder = normalize_folder(folder)

    cond do
      is_nil(normalized_folder) ->
        normalized_root

      is_nil(normalized_root) ->
        normalized_folder

      normalized_folder == normalized_root ->
        normalized_root

      String.starts_with?(normalized_folder, normalized_root <> "/") ->
        normalized_folder

      true ->
        Path.join(normalized_root, normalized_folder)
        |> normalize_folder()
    end
  end

  def relative_folder(nil, _upload_root), do: ""
  def relative_folder("", _upload_root), do: ""

  def relative_folder(folder, upload_root) do
    normalized_root = normalize_folder(upload_root)
    normalized_folder = normalize_folder(folder)

    cond do
      is_nil(normalized_folder) ->
        ""

      is_nil(normalized_root) ->
        normalized_folder

      normalized_folder == normalized_root ->
        ""

      String.starts_with?(normalized_folder, normalized_root <> "/") ->
        String.replace_prefix(normalized_folder, normalized_root <> "/", "")

      true ->
        normalized_folder
    end
  end

  def folders_from_images(images, upload_root) do
    normalized_root = normalize_folder(upload_root)
    folder_paths_by_id = folder_absolute_paths_for_images(images)

    folders_from_images =
      images
      |> Enum.map(&image_folder_absolute(&1, folder_paths_by_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&normalize_folder/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&folder_under_root?(&1, normalized_root))
      |> Enum.flat_map(&folder_prefixes(&1, normalized_root))
      |> Enum.map(&relative_folder(&1, normalized_root))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    folders =
      folders_from_database(normalized_root)
      |> Kernel.++(folders_from_images)
      |> Enum.uniq()
      |> Enum.sort()

    if "" in folders, do: folders, else: ["" | folders]
  end

  def child_folders(folders, current_folder) do
    current = normalize_folder(current_folder) || ""

    prefix =
      if current == "" do
        ""
      else
        current <> "/"
      end

    folders
    |> Enum.map(&(normalize_folder(&1) || ""))
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.reject(&(&1 == current))
    |> Enum.map(&String.replace_prefix(&1, prefix, ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&(String.split(&1, "/", parts: 2) |> hd()))
    |> Enum.map(fn child ->
      if current == "", do: child, else: current <> "/" <> child
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def breadcrumbs(current_folder) do
    current = normalize_folder(current_folder) || ""

    if current == "" do
      [%{label: "Root", folder: ""}]
    else
      segments = String.split(current, "/", trim: true)

      [%{label: "Root", folder: ""}]
      |> Kernel.++(
        Enum.scan(segments, fn segment, acc -> "#{acc}/#{segment}" end)
        |> Enum.with_index()
        |> Enum.map(fn {folder, idx} ->
          %{label: Enum.at(segments, idx), folder: folder}
        end)
      )
    end
  end

  def images_in_folder(images, current_folder, upload_root) do
    current = normalize_folder(current_folder) || ""
    folder_paths_by_id = folder_absolute_paths_for_images(images)

    abs_folder =
      if current == "" do
        normalize_folder(upload_root)
      else
        absolute_folder(current, upload_root)
      end

    Enum.filter(images, fn image ->
      normalize_folder(image_folder_absolute(image, folder_paths_by_id)) == abs_folder
    end)
  end

  def push_recent_folder(recent_folders, folder) do
    normalized = normalize_folder(folder)

    if is_nil(normalized) do
      recent_folders || []
    else
      [normalized | Enum.reject(recent_folders || [], &(&1 == normalized))]
      |> Enum.take(@max_recent_folders)
    end
  end

  def folders_from_filesystem(_upload_root), do: [""]

  def create_folder(folder, upload_root \\ nil) do
    scope = scope_for(upload_root)
    relative = relative_folder(folder, scope) |> normalize_folder()

    cond do
      is_nil(relative) ->
        {:error, :invalid_folder}

      true ->
        case ensure_folder(scope, relative) do
          {:ok, _folder} -> {:ok, absolute_folder(relative, scope)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def folder_id_for(folder, upload_root \\ nil) do
    scope = scope_for(upload_root)
    relative = relative_folder(folder, scope) |> normalize_folder()

    if is_nil(relative) do
      nil
    else
      case ensure_folder(scope, relative) do
        {:ok, folder} -> folder.id
        _ -> nil
      end
    end
  end

  defp directory_from_path(nil), do: nil

  defp directory_from_path(path) when is_binary(path) do
    case Path.dirname(path) do
      "." -> nil
      dir -> dir
    end
  end

  defp folder_under_root?(_folder, nil), do: true
  defp folder_under_root?(folder, root), do: folder == root or String.starts_with?(folder, root <> "/")

  defp folder_prefixes(folder, nil) do
    segments = String.split(folder, "/", trim: true)
    Enum.scan(segments, fn segment, acc -> "#{acc}/#{segment}" end)
  end

  defp folder_prefixes(folder, root) do
    relative = relative_folder(folder, root)
    segments = String.split(relative, "/", trim: true)

    [root | Enum.scan(segments, root, fn segment, acc -> "#{acc}/#{segment}" end)]
  end

  defp image_folder_absolute(image, folder_paths_by_id) do
    image_folder_from_db(image, folder_paths_by_id) ||
      image_folder_from_path(image)
  end

  defp image_folder_from_db(%{folder_id: folder_id}, folder_paths_by_id) when is_integer(folder_id) do
    Map.get(folder_paths_by_id, folder_id)
  end

  defp image_folder_from_db(_, _), do: nil

  defp image_folder_from_path(%{path: path}) when is_binary(path), do: directory_from_path(path)
  defp image_folder_from_path(_), do: nil

  defp folders_from_database(upload_root) do
    Folder
    |> select([f], %{scope: f.scope, path: f.path})
    |> Repo.all()
    |> Enum.map(fn %{scope: scope, path: path} ->
      absolute_folder(path, scope)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&folder_under_root?(&1, upload_root))
    |> Enum.map(&relative_folder(&1, upload_root))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp folder_absolute_paths_for_images(images) do
    folder_ids =
      images
      |> Enum.map(&Map.get(&1, :folder_id))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    if folder_ids == [] do
      %{}
    else
      Folder
      |> where([f], f.id in ^folder_ids)
      |> select([f], {f.id, f.scope, f.path})
      |> Repo.all()
      |> Map.new(fn {id, scope, path} -> {id, absolute_folder(path, scope)} end)
    end
  end

  defp ensure_folder(scope, path) do
    segments = String.split(path, "/", trim: true)

    Enum.reduce_while(segments, {:ok, nil, ""}, fn segment, {:ok, parent, parent_path} ->
      folder_path =
        case parent_path do
          "" -> segment
          path -> path <> "/" <> segment
        end

      case get_folder(scope, folder_path) do
        %Folder{} = folder ->
          {:cont, {:ok, folder, folder_path}}

        nil ->
          attrs = %{scope: scope, name: segment, path: folder_path, parent_id: parent && parent.id}

          case %Folder{} |> Folder.changeset(attrs) |> Repo.insert() do
            {:ok, folder} ->
              {:cont, {:ok, folder, folder_path}}

            {:error, _changeset} ->
              case get_folder(scope, folder_path) do
                %Folder{} = folder ->
                  {:cont, {:ok, folder, folder_path}}

                nil ->
                  {:halt, {:error, :create_failed}}
              end
          end
      end
    end)
    |> case do
      {:ok, %Folder{} = folder, _path} -> {:ok, folder}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_folder(scope, path) do
    Folder
    |> where([f], f.scope == ^scope and f.path == ^path)
    |> limit(1)
    |> Repo.one()
  end

  defp normalize_config_target(nil), do: nil
  defp normalize_config_target(config_target) when is_binary(config_target), do: config_target
  defp normalize_config_target(%{config_target: config_target}), do: normalize_config_target(config_target)

  defp normalize_config_target({type, schema, :function, function_name}) do
    "#{type}:#{inspect(schema)}:function:#{function_name}"
  end

  defp normalize_config_target({type, schema, field}) do
    "#{type}:#{inspect(schema)}:#{field}"
  end

  defp normalize_config_target(_), do: nil
end
