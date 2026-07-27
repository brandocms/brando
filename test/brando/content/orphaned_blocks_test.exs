defmodule Brando.Content.OrphanedBlocksTest do
  # `list_orphaned_blocks/0` used to hardcode the `pages_blocks` join and ignore
  # `parent_id`, so it reported every nested child — and every block belonging to
  # any other join schema — as orphaned. Acting on that list would have deleted
  # live content, and deleting even a genuine orphan breaks revision restore.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Revisions
  alias Ecto.Changeset

  defp insert_root_block(page, user, children \\ []) do
    %Brando.Pages.Page.Blocks{}
    |> Changeset.change(%{entry_id: page.id, sequence: 0})
    |> Changeset.put_assoc(:block, %{
      uid: Brando.Utils.generate_uid(),
      type: :container,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      children: children
    })
    |> Brando.Repo.insert!()
  end

  defp child_params(user) do
    %{
      uid: Brando.Utils.generate_uid(),
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      vars: [],
      refs: [],
      children: []
    }
  end

  defp orphaned_ids, do: ContentBlocks.list_orphaned_blocks() |> Enum.map(& &1.id) |> Enum.sort()

  test "a linked root block is not orphaned" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    entry_block = insert_root_block(page, user)

    refute entry_block.block_id in orphaned_ids()
  end

  # The regression: children are owned by their root through `parent_id` and
  # never have a join row, so a `pages_blocks` existence check flagged them all.
  test "a nested child of a linked root is not orphaned" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    entry_block = insert_root_block(page, user, [child_params(user)])

    root = Brando.Repo.preload(entry_block, block: :children).block
    [child] = root.children

    assert child.parent_id == root.id
    refute child.id in orphaned_ids()
  end

  test "a root block whose join row is gone is orphaned" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    entry_block = insert_root_block(page, user)

    Brando.Repo.delete!(entry_block)

    assert entry_block.block_id in orphaned_ids()
    # ...and the block itself survives, which is what lets a revision re-link it
    assert Brando.Repo.get(Brando.Content.Block, entry_block.block_id)
  end

  test "reports the source so a caller knows which join schema was checked" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    entry_block = insert_root_block(page, user)
    Brando.Repo.delete!(entry_block)

    orphan = Enum.find(ContentBlocks.list_orphaned_blocks(), &(&1.id == entry_block.block_id))

    # `Brando.Type.Module` loads it back as the module itself, not a binary
    assert orphan.source == Brando.Pages.Page.Blocks
  end

  # This is why `list_orphaned_blocks/0` is a diagnostic and not a cleanup list,
  # and why there is no sweeper job. The revision blob does carry the block's
  # content, but `set_entry_to_revision/5` never rebuilds a block from it — it
  # re-links the surviving row and aborts if that row is gone. Delete orphans on
  # a schedule and every revision still describing one becomes unrestorable.
  test "deleting an orphaned block makes revisions that reference it unrestorable" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    entry_block = insert_root_block(page, user)
    block_id = entry_block.block_id

    assert {:ok, revision} = Revisions.create_revision(page, user)

    # the editor removes the block from the page: join row goes, block remains
    Brando.Repo.delete!(entry_block)
    assert block_id in orphaned_ids()

    # restoring still works while the orphan is around
    assert {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

    # ...but not once a sweeper has taken it
    Brando.Repo.delete!(Brando.Repo.get!(Brando.Content.Block, block_id))

    assert {:error, {:revision, {:missing_block, ^block_id}}} =
             Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)
  end
end
