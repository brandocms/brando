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

  test "all folders drops the folder filter, as the command palette's search links ask" do
    params = AssetListHelpers.list_params(%{"filter:folder_id" => "all", "filter:path" => "launch"}, [1])
    assert params == %{"filter:path" => "launch"}
    assert AssetListHelpers.resolve_current_folder("all", "videos") == ""
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
