defmodule BrandoAdmin.Images.SweepTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Images.Image
  alias Brando.Media.Folder
  alias Brando.Pages.Page
  alias Brando.Repo
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.Images.Sweep

  @root "images/site/default"

  setup do
    folder_id = FolderBrowser.folder_id_for(@root)
    %{folder_id: folder_id}
  end

  defp image(folder_id), do: Factory.insert(:image, folder_id: folder_id)

  defp page(title, language \\ "en") do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title) <> "-" <> language, language: language)
    Brando.Content.create_identifier(Page, page)
    page
  end

  # A block on `page` showing each of `images`.
  defp show(page, images) do
    source = "Elixir.Brando.Pages.Page.Blocks"
    uid = Brando.Utils.generate_uid()
    block = Repo.insert!(%Block{type: :module, source: source, uid: uid})
    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    Enum.each(images, &Factory.insert(:ref, block_id: block.id, image_id: &1.id))
  end

  defp folder_of(image), do: Repo.one(from i in Image, where: i.id == ^image.id, select: i.folder_id)
  defp path_of(folder_id), do: Repo.get!(Folder, folder_id).path

  test "plans a folder per entry, leaves unused images, and gives a shared image to the larger owner", c do
    [a, b, shared, lone, unused] = for _ <- 1..5, do: image(c.folder_id)
    about = page("About us")
    contact = page("Contact")
    show(about, [a, b, shared])
    show(contact, [shared, lone])

    assert {:ok, plan} = Sweep.plan(c.folder_id)
    assert plan.folder == @root
    assert plan.total == 5
    assert plan.unused == 1

    assert [first, second] = plan.groups
    assert first.key == "pages/about-us"
    assert first.path == "images/site/default/pages/about-us"
    assert first.label == "About us"
    assert Enum.sort(first.ids) == Enum.sort([a.id, b.id, shared.id])
    assert first.shared == 1
    assert second.key == "pages/contact"
    assert second.ids == [lone.id]

    refute unused.id in Enum.flat_map(plan.groups, & &1.ids)
  end

  test "an entry and its translation share the default-language entry's folder", c do
    [norwegian_only, both] = for _ <- 1..2, do: image(c.folder_id)
    english = page("About us", "en")
    norwegian = page("Om oss", "no")
    Repo.insert!(struct(Module.concat([Page, Alternate]), entry_id: norwegian.id, linked_entry_id: english.id))
    show(norwegian, [norwegian_only, both])
    show(english, [both])

    assert {:ok, %{groups: [group]}} = Sweep.plan(c.folder_id)
    assert group.key == "pages/about-us"
    assert Enum.sort(group.ids) == Enum.sort([norwegian_only.id, both.id])
    assert group.shared == 0
  end

  test "apply moves the chosen groups and undo puts them back, removing the folders it made", c do
    [a, b, unused] = for _ <- 1..3, do: image(c.folder_id)
    show(page("About us"), [a])
    show(page("Contact"), [b])

    {:ok, plan} = Sweep.plan(c.folder_id)
    assert {:ok, result} = Sweep.apply(plan, only: ["pages/about-us"])
    assert result.moved == 1
    assert path_of(folder_of(a)) == "site/default/pages/about-us"
    assert folder_of(b) == c.folder_id
    assert folder_of(unused) == c.folder_id

    # A second plan only sees what is still loose in the folder.
    assert {:ok, %{total: 2, groups: [%{key: "pages/contact"}]}} = Sweep.plan(c.folder_id)

    assert {:ok, 1} = Sweep.undo(result)
    assert folder_of(a) == c.folder_id
    refute Repo.get_by(Folder, path: "site/default/pages/about-us")
    refute Repo.get_by(Folder, path: "site/default/pages")
    assert Repo.get(Folder, c.folder_id)
  end

  test "undo leaves an image an editor has moved on since", c do
    a = image(c.folder_id)
    show(page("About us"), [a])
    {:ok, plan} = Sweep.plan(c.folder_id)
    {:ok, result} = Sweep.apply(plan)

    elsewhere = FolderBrowser.folder_id_for("images/site/default/keep")
    Repo.update_all(from(i in Image, where: i.id == ^a.id), set: [folder_id: elsewhere])

    assert {:ok, 0} = Sweep.undo(result)
    assert folder_of(a) == elsewhere
  end

  test "a missing folder gives an error" do
    assert {:error, :not_found} = Sweep.plan(0)
  end
end
