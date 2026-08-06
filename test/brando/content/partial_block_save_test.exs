defmodule Brando.Content.PartialBlockSaveTest do
  # What happens when a multi-root block save is only *partly* valid — one root
  # rejected, its siblings fine. Untested at any level before this, and the
  # failure mode it guards against is the one the whole form audit is about:
  # not "the save failed" (which is fine and visible) but "the save failed and
  # took the user's other unsaved blocks with it" (which is silent).
  #
  # Drives the same save path `BlockField`'s `fetch_root_blocks` and the Form
  # run: materialize each root, cast recursively over the persisted entry block,
  # `reject_deleted` → `strip_render_artifacts` → `put_assoc` → update.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Ecto.Changeset

  # `Page` is used for its real changeset, not just as a struct — see the
  # "an invalid entry with valid blocks" describe block.

  defp block_params(uid, user, extra \\ %{}) do
    Map.merge(
      %{
        uid: uid,
        type: :module,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        vars: [],
        refs: [],
        children: []
      },
      extra
    )
  end

  defp save_roots(page, roots, user) do
    changesets =
      roots
      |> Enum.with_index()
      |> Enum.map(fn {params, i} ->
        Brando.Pages.Page.Blocks.changeset(
          %Brando.Pages.Page.Blocks{},
          %{"entry_id" => page.id, "sequence" => i, "block" => params},
          user.id,
          true
        )
      end)
      |> ContentBlocks.reject_deleted(true)
      |> ContentBlocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    page
    |> Brando.Repo.preload(:entry_blocks)
    |> Changeset.change()
    |> Changeset.put_assoc(:entry_blocks, changesets)
    |> Brando.Repo.update()
  end

  defp persisted_uids do
    Block |> Brando.Repo.all() |> Enum.map(& &1.uid) |> Enum.sort()
  end

  # `[]` means "this block was cast and has no errors". A *missing* `:block`
  # change means the block vanished from the returned changeset entirely, which
  # is the data-loss shape this whole file exists to catch — so it gets its own
  # value. Collapsing both to `[]` (as this did) made every assertion below
  # satisfiable by the defect: `[[], [:type], []]` passed just as happily when
  # rootA and rootC had been dropped as when they were intact.
  defp block_errors(changeset) do
    changeset
    |> Changeset.get_change(:entry_blocks, [])
    |> Enum.map(fn entry_block ->
      case Changeset.get_change(entry_block, :block) do
        nil -> :no_block_change
        block_cs -> Keyword.keys(block_cs.errors)
      end
    end)
  end

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    {:ok, user: user, page: page}
  end

  describe "one invalid root among valid siblings" do
    # Atomicity. The valid roots must not land without the invalid one, or the
    # user's next save would insert them a second time.
    test "persists nothing at all", %{user: user, page: page} do
      {:error, _changeset} =
        save_roots(
          page,
          [
            block_params("rootA", user),
            block_params("rootB", user, %{type: "not_a_block_type"}),
            block_params("rootC", user)
          ],
          user
        )

      assert persisted_uids() == []
    end

    # The editor has to be able to point at the block that failed, so the error
    # must stay attached to that root's position rather than being flattened
    # onto the entry.
    test "attributes the error to the failing root and to no other", %{user: user, page: page} do
      {:error, changeset} =
        save_roots(
          page,
          [
            block_params("rootA", user),
            block_params("rootB", user, %{type: "not_a_block_type"}),
            block_params("rootC", user)
          ],
          user
        )

      assert block_errors(changeset) == [[], [:type], []]
    end

    # The one that matters most. A rejected save returns the changeset the form
    # re-renders from, so the valid siblings' content has to still be in it —
    # otherwise fixing one block silently discards the edits to the others,
    # which is Phase 0's data-loss shape arriving through the save path.
    test "keeps the valid siblings' content in the returned changeset", %{user: user, page: page} do
      {:error, changeset} =
        save_roots(
          page,
          [
            block_params("rootA", user, %{description: "keep me"}),
            block_params("rootB", user, %{type: "not_a_block_type"}),
            block_params("rootC", user, %{description: "me too"})
          ],
          user
        )

      descriptions =
        changeset
        |> Changeset.get_change(:entry_blocks)
        |> Enum.map(&(&1 |> Changeset.get_change(:block) |> Changeset.get_change(:description)))

      assert descriptions == ["keep me", nil, "me too"]
    end

    # And the failure is recoverable: fix the one block, save again, everything
    # lands with its sequence intact.
    test "a corrected re-save persists every root in order", %{user: user, page: page} do
      {:error, _} =
        save_roots(
          page,
          [
            block_params("rootA", user),
            block_params("rootB", user, %{type: "not_a_block_type"}),
            block_params("rootC", user)
          ],
          user
        )

      {:ok, _} =
        save_roots(
          page,
          [
            block_params("rootA", user),
            block_params("rootB", user),
            block_params("rootC", user)
          ],
          user
        )

      entry_blocks =
        Brando.Pages.Page.Blocks
        |> Brando.Repo.all()
        |> Brando.Repo.preload(:block)
        |> Enum.sort_by(& &1.sequence)

      assert Enum.map(entry_blocks, & &1.block.uid) == ["rootA", "rootB", "rootC"]
      assert Enum.map(entry_blocks, & &1.sequence) == [0, 1, 2]
    end
  end

  describe "an invalid nested child" do
    # A child is cast through the same recursive changeset, so its failure has
    # to reach the top with the same atomicity — a root that half-saved would
    # leave the op store and the database disagreeing about the tree.
    test "aborts the whole save", %{user: user, page: page} do
      {:error, _changeset} =
        save_roots(
          page,
          [
            block_params("rootA", user),
            block_params("rootB", user, %{
              type: :container,
              children: [block_params("childX", user, %{type: "not_a_block_type"})]
            })
          ],
          user
        )

      assert persisted_uids() == []
    end
  end

  describe "an invalid entry with valid blocks" do
    # The realistic version: every block is fine, the user just left a required
    # entry field empty. The blocks must not persist ahead of the entry, and
    # they must survive in the changeset so the form can re-render them.
    #
    # The invalidity comes from `Page.changeset/5` — `uri` is `required: true`
    # on the blueprint (`page.ex:94`) — and not from a `validate_required/2` the
    # test bolts on. That distinction is the whole point of the rewrite: the
    # earlier version invented both the error and the changeset, so it asserted
    # Ecto's guarantee that `put_assoc` changes survive an invalid parent. Ecto
    # is not the thing under test here; Brando's entry changeset is, and if it
    # ever stopped surfacing the missing `uri`, or dropped `entry_blocks` while
    # rebuilding, this now goes red.
    test "persists no blocks and keeps them in the changeset", %{user: user, page: page} do
      changesets = [
        %Brando.Pages.Page.Blocks{}
        |> Brando.Pages.Page.Blocks.changeset(
          %{"entry_id" => page.id, "sequence" => 0, "block" => block_params("rootA", user)},
          user.id,
          true
        )
        |> Brando.Utils.set_action()
      ]

      {:error, changeset} =
        page
        |> Brando.Repo.preload(:entry_blocks)
        |> Page.changeset(%{title: "Still titled", uri: nil, template: "default.html"}, user)
        |> Changeset.put_assoc(:entry_blocks, changesets)
        |> Brando.Repo.update()

      assert persisted_uids() == []
      assert :uri in Keyword.keys(changeset.errors)
      assert length(Changeset.get_change(changeset, :entry_blocks)) == 1
    end
  end

  describe "block identity" do
    # `uid` is declared `required: true` on the attribute, but the cast path the
    # editor uses never enforced it — a root would save with `uid: nil`. That is
    # not cosmetic: the op store keys on uid, the component's DOM id is
    # `block-<uid>`, and block recovery keys on `entry_block_form-<uid>`, so a
    # nil-uid block is unaddressable by every one of them. C6 fixed one way of
    # producing one; this closes the source.
    test "a root without a uid is rejected", %{user: user, page: page} do
      {:error, changeset} =
        save_roots(page, [block_params("rootA", user), block_params(nil, user)], user)

      assert block_errors(changeset) == [[], [:uid]]
      assert persisted_uids() == []
    end

    # `unique_constraint(:uid)` has been declared on the block changeset all
    # along; consuming apps back it with `brando_123_blocks_uid_constraint`.
    # Two roots sharing a uid come back as a changeset error, not a raise.
    test "two roots cannot share a uid", %{user: user, page: page} do
      {:error, changeset} =
        save_roots(page, [block_params("dupe", user), block_params("dupe", user)], user)

      assert [:uid] in block_errors(changeset)
      assert persisted_uids() == []
    end
  end
end
