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
  passes its own `folder_under_root?/2` from `BrandoAdmin.Components.PickerHelpers`,
  so the rule stays defined in one place.
  """
  def recent_folders_for_root(recent_folders, upload_root, under_root?) do
    recent_folders
    |> Enum.map(&FolderBrowser.normalize_folder/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&under_root?.(&1, upload_root))
    |> Enum.reject(&(FolderBrowser.relative_folder(&1, upload_root) == ""))
    |> Enum.take(@max_recent_folders_for_root)
  end
end
