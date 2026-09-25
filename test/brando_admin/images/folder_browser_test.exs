defmodule BrandoAdmin.Images.FolderBrowserTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Media.Folder
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.LiveView.AssetListHelpers

  test "a folder that is the upload root itself lists its videos at the root" do
    root = Brando.Repo.insert!(%Folder{scope: "videos", name: "default", path: "default"})
    below = Brando.Repo.insert!(%Folder{scope: "videos", name: "cases", path: "default/cases"})

    in_root_folder = Factory.insert(:video, folder_id: root.id)
    without_folder = Factory.insert(:video)
    Factory.insert(:video, folder_id: below.id)

    root_ids = FolderBrowser.root_folder_ids("videos/default")
    assert root_ids == [root.id]

    %{"filter:folder_id" => filter} = AssetListHelpers.list_params(%{}, root_ids)
    {:ok, videos} = Brando.Videos.list_videos(%{filter: %{folder_id: filter}})

    assert videos |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([in_root_folder.id, without_folder.id])
  end
end
