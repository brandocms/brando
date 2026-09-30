defmodule Brando.Content.BlockAuditTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Content.BlockArchive
  alias Brando.Content.BlockAudit
  alias Brando.Content.Ref
  alias Brando.Drafts.EntryDraft
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Revisions

  @source "Elixir.Brando.Pages.Page.Blocks"

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, title: "About us", uri: "about-us", language: "en")
    %{user: user, page: page}
  end

  defp block(attrs \\ []) do
    Repo.insert!(struct(%Block{type: :module, source: @source, uid: Brando.Utils.generate_uid()}, attrs))
  end

  defp link(page, block), do: Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
  defp unlink(block), do: Repo.delete_all(from j in Page.Blocks, where: j.block_id == ^block.id)

  defp text_ref(block, text) do
    Factory.insert(:ref,
      block_id: block.id,
      data: %Brando.Villain.Blocks.TextBlock{
        type: "text",
        data: %Brando.Villain.Blocks.TextBlock.Data{text: text}
      }
    )
  end

  defp tree(scan, block), do: Enum.find(scan.trees, &(&1.id == block.id))

  test "a root no table links to is loose, with its children; a linked one is not", c do
    linked = block()
    link(c.page, linked)
    linked_child = block(parent_id: linked.id)

    loose = block()
    child = block(parent_id: loose.id)
    image = Factory.insert(:image)
    text_ref(child, "<p>We moved to <b>Oslo</b></p>")
    picture = Factory.insert(:picture_ref, block_id: loose.id)
    Repo.update_all(from(r in Ref, where: r.id == ^picture.id), set: [image_id: image.id])

    scan = BlockAudit.scan()

    assert {"pages_blocks", "block_id"} in BlockAudit.link_tables()
    refute tree(scan, linked)
    refute tree(scan, linked_child)

    assert %{status: :removable, held_by: []} = found = tree(scan, loose)
    assert Enum.sort(found.block_ids) == Enum.sort([loose.id, child.id])
    assert found.excerpt == "We moved to Oslo"
    assert found.image_ids == [image.id]
    assert scan.totals.loose_trees == 1
    assert scan.totals.loose_blocks == 2
    assert scan.totals.removable == 1
  end

  test "a block a revision holds is not removable, and removal leaves it", c do
    held = block()
    link(c.page, held)
    page = Repo.preload(Repo.get!(Page, c.page.id), Brando.Blueprint.preloads_for(Page))
    assert {:ok, _} = Revisions.create_revision(page, c.user)
    unlink(held)

    scan = BlockAudit.scan()
    assert %{status: :held_by_revision, held_by: [holder]} = tree(scan, held)
    assert holder.entry_id == c.page.id
    assert holder.entry_type == "Elixir.Brando.Pages.Page"

    assert {:ok, %{removed: 0, skipped: [skipped]}} = BlockAudit.remove([held.id], c.user)
    assert skipped == held.id
    assert Repo.get(Block, held.id)
  end

  test "a block a recovery copy mentions is not removable", c do
    loose = block()

    Repo.insert!(%EntryDraft{
      id: Ecto.UUID.generate(),
      scope: "public",
      owner_id: c.user.id,
      entry_type: "Elixir.Brando.Pages.Page",
      entry_id: c.page.id,
      form_name: "page_form",
      generation: 1,
      base_fingerprint: "x",
      payload: %{"blocks" => [%{"uid" => loose.uid}]},
      checksum: "x",
      expires_at: DateTime.add(DateTime.utc_now(), 3600)
    })

    assert %{status: :held_by_draft} = tree(BlockAudit.scan(), loose)
  end

  test "remove archives the tree and deletes it with its records; restore puts it back", c do
    loose = block(description: "Old hero")
    child = block(parent_id: loose.id)
    ref = text_ref(child, "<p>Hello</p>")
    linked = block()
    link(c.page, linked)

    assert {:ok, %{removed: 1, blocks: 2, skipped: [skipped]}} = BlockAudit.remove([loose.id, linked.id], c.user)
    assert skipped == linked.id
    refute Repo.get(Block, loose.id)
    refute Repo.get(Block, child.id)
    refute Repo.get(Ref, ref.id)
    assert Repo.get(Block, linked.id)

    assert [archive] = BlockAudit.list_archive()
    assert archive.root_block_id == loose.id
    assert archive.block_count == 2
    assert archive.removed_by_id == c.user.id
    assert archive.summary["description"] == "Old hero"
    assert archive.summary["excerpt"] == "Hello"

    assert {:ok, restored} = BlockAudit.restore(archive.id)
    assert restored == loose.id
    assert %{uid: uid, description: "Old hero"} = Repo.get(Block, loose.id)
    assert uid == loose.uid
    assert Repo.get(Block, child.id).parent_id == loose.id
    assert Repo.get(Ref, ref.id).data.data.text == "<p>Hello</p>"
    assert Repo.aggregate(BlockArchive, :count) == 0
    assert %{status: :removable} = tree(BlockAudit.scan(), loose)
  end

  test "restoring an unknown archive is an error" do
    assert {:error, :not_found} = BlockAudit.restore(0)
  end
end
