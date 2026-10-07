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

  test "all folders lists every library folder and the root, never a hidden folder" do
    site = Brando.Repo.insert!(%Folder{scope: "images", name: "site", path: "site"})
    nested = Brando.Repo.insert!(%Folder{scope: "images", name: "press", path: "site/press", parent_id: site.id})
    hidden_id = Brando.Media.Folders.hidden_folder_id("visitor-uploads")

    in_nested = Factory.insert(:image, path: "images/site/press/launch-1.jpg", folder_id: nested.id)
    without_folder = Factory.insert(:image, path: "images/launch-2.jpg")
    Factory.insert(:image, path: "images/hidden/launch-3.jpg", folder_id: hidden_id)

    params = AssetListHelpers.list_params(%{"filter:folder_id" => "all", "filter:path" => "launch"}, [])
    assert %{"filter:folder_id" => {:library, [^hidden_id]}, "filter:path" => "launch"} = params
    assert AssetListHelpers.resolve_current_folder("all", "images") == ""

    {:ok, images} = Brando.Images.list_images(%{filter: %{folder_id: params["filter:folder_id"], path: "launch"}})
    assert images |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([in_nested.id, without_folder.id])
  end

  describe "where folders are stored" do
    test "a folder made in a picker lands in the library's tree" do
      site = Brando.Repo.insert!(%Folder{scope: "images", name: "site", path: "site"})
      default = Brando.Repo.insert!(%Folder{scope: "images", name: "default", path: "site/default", parent_id: site.id})

      {:ok, "images/site/default/press"} = FolderBrowser.create_folder("press", "images/site/default")

      press = Brando.Repo.get_by!(Folder, path: "site/default/press")
      assert press.scope == "images"
      assert press.parent_id == default.id

      # The library, rooted at "images", resolves it too, and to the same row.
      assert FolderBrowser.folder_id_for("site/default/press", "images") == press.id
      assert FolderBrowser.folder_id_for("press", "images/site/default") == press.id
      assert FolderBrowser.folder_path_for_id(press.id, "images") == "site/default/press"
      assert FolderBrowser.folder_path_for_id(press.id, "images/site/default") == "press"
    end

    test "the picker's root is the library folder of the same path" do
      site = Brando.Repo.insert!(%Folder{scope: "images", name: "site", path: "site"})
      default = Brando.Repo.insert!(%Folder{scope: "images", name: "default", path: "site/default", parent_id: site.id})

      assert FolderBrowser.folder_id_for("", "images/site/default") == default.id
    end

    test "a folder stored the older way, under a picker's root, still resolves" do
      legacy = Brando.Repo.insert!(%Folder{scope: "images/site/default", name: "old", path: "old"})

      assert FolderBrowser.folder_path_for_id(legacy.id, "images") == "site/default/old"
      assert FolderBrowser.folder_path_for_id(legacy.id, "images/site/default") == "old"
    end
  end
end
