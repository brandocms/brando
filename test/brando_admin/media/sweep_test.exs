defmodule BrandoAdmin.Media.SweepTest do
  # "Sort by use" for videos and files: the same sweep as images
  # (test/brando_admin/images/sweep_test.exs), by asset type.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Files.File, as: MediaFile
  alias Brando.Media.Folder
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Sites.GlobalSet
  alias Brando.Videos.Video
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.Media.Sweep

  setup do
    %{
      videos: FolderBrowser.folder_id_for("videos/default/sweep"),
      files: FolderBrowser.folder_id_for("files/default/sweep")
    }
  end

  defp video(folder_id), do: Factory.insert(:video, folder_id: folder_id)

  defp file(folder_id, name) do
    Repo.insert!(%MediaFile{filename: name, filesize: 100, config_target: "default", folder_id: folder_id})
  end

  defp page(title, language \\ "en") do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title) <> "-" <> language, language: language)
    Brando.Content.create_identifier(Page, page)
    page
  end

  # A block on `page` with a ref to each of `assets`.
  defp show(page, assets) do
    source = "Elixir.Brando.Pages.Page.Blocks"
    block = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})

    Enum.each(assets, fn
      %Video{id: id} -> Factory.insert(:ref, block_id: block.id, video_id: id)
      %MediaFile{id: id} -> Factory.insert(:ref, block_id: block.id, file_id: id)
    end)
  end

  defp folder_of(%schema{id: id}), do: Repo.one(from a in schema, where: a.id == ^id, select: a.folder_id)
  defp path_of(folder_id), do: Repo.get!(Folder, folder_id).path

  describe "videos" do
    test "plans a folder per entry, leaves unused videos, and gives a shared one to the larger owner", c do
      [a, b, shared, lone, unused] = for _ <- 1..5, do: video(c.videos)
      show(page("About us"), [a, b, shared])
      show(page("Contact"), [shared, lone])

      assert {:ok, plan} = Sweep.plan(:video, c.videos)
      assert plan.asset_type == :video
      assert plan.folder == "videos/default/sweep"
      assert plan.total == 5
      assert plan.unused == 1

      assert [first, second] = plan.groups
      assert first.key == "pages/about-us"
      assert first.path == "videos/default/sweep/pages/about-us"
      assert Enum.sort(first.ids) == Enum.sort([a.id, b.id, shared.id])
      assert first.shared == 1
      assert second.key == "pages/contact"
      assert second.ids == [lone.id]
      refute unused.id in Enum.flat_map(plan.groups, & &1.ids)
    end

    test "an entry and its translation share the default-language entry's folder", c do
      [norwegian_only, both] = for _ <- 1..2, do: video(c.videos)
      english = page("About us", "en")
      norwegian = page("Om oss", "no")
      Repo.insert!(struct(Module.concat([Page, Alternate]), entry_id: norwegian.id, linked_entry_id: english.id))
      show(norwegian, [norwegian_only, both])
      show(english, [both])

      assert {:ok, %{groups: [group]}} = Sweep.plan(:video, c.videos)
      assert group.key == "pages/about-us"
      assert Enum.sort(group.ids) == Enum.sort([norwegian_only.id, both.id])
      assert group.shared == 0
    end

    test "a shared video follows the videos' priority, else the images'", c do
      [a, b, shared] = for _ <- 1..3, do: video(c.videos)
      show(page("About us"), [a, b, shared])
      set = Factory.insert(:global_set, vars: [])

      Repo.insert!(%Brando.Content.Var{
        type: :video,
        key: "film",
        label: %{"en" => "Film"},
        global_set_id: set.id,
        video_id: shared.id
      })

      owner = fn ->
        {:ok, plan} = Sweep.plan(:video, c.videos)
        Enum.find(plan.groups, &(shared.id in &1.ids)).type
      end

      # The page uses more of the folder's videos.
      assert owner.() == Brando.Blueprint.get_singular(Page)

      images = Application.get_env(:brando, Brando.Images, [])
      put_test_env(Brando.Images, Keyword.put(images, :sweep_priority, [GlobalSet]))
      assert owner.() == Brando.Blueprint.get_singular(GlobalSet)

      videos = Application.get_env(:brando, Brando.Videos, [])
      put_test_env(Brando.Videos, Keyword.put(videos, :sweep_priority, [Page]))
      assert owner.() == Brando.Blueprint.get_singular(Page)
    end

    test "apply moves the chosen groups and undo puts them back, removing the folders it made", c do
      [a, b, unused] = for _ <- 1..3, do: video(c.videos)
      show(page("About us"), [a])
      show(page("Contact"), [b])

      {:ok, plan} = Sweep.plan(:video, c.videos)
      assert {:ok, result} = Sweep.apply(plan, only: ["pages/about-us"], names: %{"pages/about-us" => "sider/om-oss"})
      assert result.asset_type == :video
      assert result.moved == 1
      assert path_of(folder_of(a)) == "default/sweep/sider/om-oss"
      assert folder_of(b) == c.videos
      assert folder_of(unused) == c.videos

      assert {:ok, %{total: 2, groups: [%{key: "pages/contact"}]}} = Sweep.plan(:video, c.videos)

      assert {:ok, 1} = Sweep.undo(result)
      assert folder_of(a) == c.videos
      refute Repo.get_by(Folder, scope: "videos", path: "default/sweep/sider/om-oss")
      refute Repo.get_by(Folder, scope: "videos", path: "default/sweep/sider")
      assert Repo.get(Folder, c.videos)
    end

    test "undo removes only the folders this sort made, and keeps one holding another type", c do
      a = video(c.videos)
      show(page("About us"), [a])
      existing = FolderBrowser.folder_id_for("videos/default/sweep/pages")

      {:ok, plan} = Sweep.plan(:video, c.videos)
      {:ok, result} = Sweep.apply(plan)
      created = FolderBrowser.folder_id_for("videos/default/sweep/pages/about-us")
      assert result.created == [created]

      # Made meanwhile, elsewhere in the library: not the sort's.
      other = FolderBrowser.folder_id_for("videos/default/elsewhere")
      # An image filed in the folder the sort made keeps it.
      image = Factory.insert(:image, folder_id: created)

      assert {:ok, 1} = Sweep.undo(result)
      assert Repo.get(Folder, existing)
      assert Repo.get(Folder, other)
      assert Repo.get(Folder, created)

      Repo.delete!(image)
      {:ok, plan} = Sweep.plan(:video, c.videos)
      {:ok, result} = Sweep.apply(plan)
      # Into a folder that was there already: undone, and the folder stays.
      assert result.created == []
      assert {:ok, 1} = Sweep.undo(result)
      assert folder_of(a) == c.videos
      assert Repo.get(Folder, created)
    end

    test "only a folder in the type's library can be sorted", c do
      hidden = Brando.Media.Folders.hidden_folder_id("uploads")

      assert {:error, :not_found} = Sweep.plan(:video, c.files)
      assert {:error, :not_found} = Sweep.plan(:video, hidden)
      assert {:error, :not_found} = Sweep.plan(:video, nil)
      assert {:error, :not_found} = Sweep.plan(:video, 0)
    end

    test "samples carry the video's thumbnail", c do
      thumbnail = Factory.insert(:image)
      a = Factory.insert(:video, folder_id: c.videos, thumbnail_id: thumbnail.id)
      show(page("About us"), [a])

      {:ok, plan} = Sweep.plan(:video, c.videos)
      assert %{thumbnail: %{id: id}} = Sweep.samples(plan)[a.id]
      assert id == thumbnail.id
    end
  end

  describe "files" do
    test "plans, applies and undoes like videos", c do
      [a, b, unused] = [file(c.files, "a.pdf"), file(c.files, "b.xlsx"), file(c.files, "old.pdf")]
      show(page("About us"), [a, b])

      assert {:ok, plan} = Sweep.plan(:file, c.files)
      assert plan.folder == "files/default/sweep"
      assert plan.unused == 1
      assert [%{key: "pages/about-us", ids: ids}] = plan.groups
      assert Enum.sort(ids) == Enum.sort([a.id, b.id])
      assert map_size(Sweep.samples(plan)) == 2

      assert {:ok, %{moved: 2} = result} = Sweep.apply(plan)
      assert path_of(folder_of(a)) == "default/sweep/pages/about-us"
      assert folder_of(unused) == c.files

      assert {:ok, 2} = Sweep.undo(result)
      assert folder_of(a) == c.files
      refute Repo.get_by(Folder, scope: "files", path: "default/sweep/pages")
    end

    test "a file folder is not a video folder", c do
      assert {:error, :not_found} = Sweep.plan(:file, c.videos)
    end
  end

  describe "tenancy" do
    @prefix "tenant_sweep_production"

    setup do
      put_test_env(:tenancy_mode, :multi)
      BrandoIntegration.Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))

      for table <- ~w(media_folders videos images files) do
        BrandoIntegration.Repo.query!(~s|CREATE TABLE "#{@prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
      end

      :ok
    end

    test "a sort and its undo stay in the current site's schema", c do
      a = video(c.videos)
      show(page("About us"), [a])

      # The same folders in the tenant: not the public sort's to touch.
      tenant_folder =
        Brando.Tenant.with_prefix(@prefix, fn ->
          FolderBrowser.folder_id_for("videos/default/sweep/pages/about-us")
          FolderBrowser.folder_id_for("videos/default/sweep")
        end)

      {:ok, plan} = Sweep.plan(:video, c.videos)
      {:ok, result} = Sweep.apply(plan)
      assert {:ok, 1} = Sweep.undo(result)

      Brando.Tenant.with_prefix(@prefix, fn ->
        assert Repo.get_by(Folder, scope: "videos", path: "default/sweep/pages/about-us")
        assert {:ok, %{total: 0, groups: []}} = Sweep.plan(:video, tenant_folder)
      end)

      refute Repo.get_by(Folder, scope: "videos", path: "default/sweep/pages/about-us")
    end
  end
end
