defmodule BrandoAdmin.Components.PickerFolders do
  @moduledoc """
  Folder state shared by the image, video and file pickers.
  """

  alias BrandoAdmin.Images.FolderBrowser

  @max_recent_folders_for_root 5

  @doc """
  Returns up to five recently used folders that sit below `upload_root`,
  normalised and excluding the root itself.

  `under_root?` decides whether a folder belongs to the root. Each picker
  passes `folder_under_root?/2`, so the rule stays defined in one place.
  """
  def recent_folders_for_root(recent_folders, upload_root, under_root?) do
    recent_folders
    |> Enum.map(&FolderBrowser.normalize_folder/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&under_root?.(&1, upload_root))
    |> Enum.reject(&(FolderBrowser.relative_folder(&1, upload_root) == ""))
    |> Enum.take(@max_recent_folders_for_root)
  end

  @doc "Whether `folder` is `root` or below it. Without a root, any folder is."
  def folder_under_root?(folder, nil), do: not is_nil(FolderBrowser.normalize_folder(folder))

  def folder_under_root?(folder, root) do
    normalized_folder = FolderBrowser.normalize_folder(folder)
    normalized_root = FolderBrowser.normalize_folder(root)

    normalized_folder == normalized_root ||
      String.starts_with?(normalized_folder || "", (normalized_root || "") <> "/")
  end
end
