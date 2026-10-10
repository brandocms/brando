defmodule BrandoAdmin.WorkingCopyPlacementTest do
  # A revision loaded as a working copy (the revisions drawer) and saved
  # has to give the entry back the revision's blocks where the revision had
  # them. A child that moved to another container since stayed where it is
  # now, written over in place with the revision's content but the module
  # version it has now, so it never showed as needing an upgrade.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Pages.Page

  setup do
    c = Brando.ProposalFixtures.context()
    page = Factory.insert(:page, creator: c.user, title: "Placement", uri: "placement")
    Map.merge(c, %{page: page})
  end

  defp text(text), do: %{"type" => "text", "data" => %{"text" => text}}

  defp module_block(c, uid, body),
    do: %{
      "uid" => uid,
      "type" => "module",
      "module_id" => c.text_module.id,
      "creator_id" => c.user.id,
      "source" => to_string(Page.Blocks),
      "refs" => [%{"uid" => uid <> "-ref", "name" => "body", "data" => text(body)}]
    }

  defp container(c, uid, children),
    do: %{
      "uid" => uid,
      "type" => "container",
      "creator_id" => c.user.id,
      "source" => to_string(Page.Blocks),
      "children" => Enum.with_index(children, fn child, n -> Map.put(child, "sequence", n) end)
    }

  defp roots!(c, roots) do
    for {params, n} <- Enum.with_index(roots) do
      block = %Block{} |> Block.recursive_block_changeset(params, c.user) |> Repo.insert!()
      Repo.insert!(%Page.Blocks{entry_id: c.page.id, block_id: block.id, sequence: n})
    end
  end

  defp stamp!(uid, fields), do: Repo.update_all(from(b in Block, where: b.uid == ^uid), set: fields)

  defp row(uid), do: Repo.one!(from(b in Block, where: b.uid == ^uid, preload: [:refs, :parent]))

  defp body(uid), do: hd(row(uid).refs).data.data.text

  # The page's tree: each root's uid with its children's, recursively.
  defp tree(page) do
    blocks = Repo.all(from(b in Block, order_by: b.sequence))
    by_parent = Enum.group_by(blocks, & &1.parent_id)
    subtree = fn subtree, block -> {block.uid, Enum.map(by_parent[block.id] || [], &subtree.(subtree, &1))} end

    Repo.all(from(j in Page.Blocks, where: j.entry_id == ^page.id, order_by: j.sequence, preload: :block))
    |> Enum.map(&subtree.(subtree, &1.block))
  end

  defp revision!(c) do
    entry = Page |> Repo.get!(c.page.id) |> Repo.preload(Brando.Blueprint.preloads_for(Page))
    {:ok, revision} = Brando.Revisions.create_revision(entry, c.user)
    revision.revision
  end

  # A move as the outline saves it: the block's row under its old parent is
  # deleted and a new one, the same uid and sync uid, inserted (here with
  # new content as well).
  defp move!(c, uid, parent_uid, sequence, body) do
    old = row(uid)
    Repo.delete!(old)

    %Block{}
    |> Block.recursive_block_changeset(Map.put(module_block(c, uid, body), "sequence", sequence), c.user)
    |> Ecto.Changeset.put_change(:parent_id, row(parent_uid).id)
    |> Repo.insert!()

    stamp!(uid, sync_uid: old.sync_uid, module_version: old.module_version)
  end

  defp open(c) do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp load_and_save(c, revision) do
    view = open(c)
    drawer = cid_of(view, "#page_form-revisions-drawer-tab-activity")
    view |> with_target(drawer) |> render_hook("select_revision", %{"revision" => revision})
    await(fn -> render(view) =~ ~r/draft-save-state" data-state="dirty"/ end)

    view |> with_target(cid_of(view, "#page_form-el")) |> render_hook("save_redirect_target", %{})
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> form("#page_form_form") |> render_submit()
    view
  end

  test "a child moved to another container since goes back, with the revision's content and version", c do
    roots!(c, [
      container(c, "boxA", [module_block(c, "keepA", "Stays in A"), module_block(c, "moved", "As in the revision")]),
      container(c, "boxB", [module_block(c, "keepB", "Stays in B")])
    ])

    stamp!("moved", sync_uid: "moved-sync", module_version: 3)
    stamp!("keepA", module_version: 1)
    stamp!("keepB", module_version: 1)
    revision = revision!(c)
    saved = tree(c.page)

    # since: moved to the top of B, edited, and its module migrated; the
    # others' modules too, and one of them edited
    move!(c, "moved", "boxB", 0, "Moved on")
    stamp!("moved", module_version: 4)
    stamp!("keepA", module_version: 2, description: "Edited since")
    stamp!("keepB", module_version: 2, sequence: 1)
    assert tree(c.page) != saved

    load_and_save(c, revision)
    await(fn -> tree(c.page) == saved end)

    moved = row("moved")
    assert moved.parent.uid == "boxA"
    assert body("moved") == "As in the revision"
    assert {moved.sync_uid, moved.module_version} == {"moved-sync", 3}
    # written with the revision's content, at the revision's version
    assert {row("keepA").description, row("keepA").module_version} == {nil, 1}
    # only moved back into place: its content is the one it has
    assert row("keepB").module_version == 2
  end

  test "a child deleted since comes back as it was, and one added since goes", c do
    roots!(c, [
      container(c, "boxA", [module_block(c, "keepA", "Stays in A"), module_block(c, "gone", "Deleted since")]),
      container(c, "boxB", [module_block(c, "keepB", "Stays in B")])
    ])

    stamp!("gone", sync_uid: "gone-sync", module_version: 2)
    revision = revision!(c)
    saved = tree(c.page)

    Repo.delete!(row("gone"))

    %Block{}
    |> Block.recursive_block_changeset(Map.put(module_block(c, "added", "Added since"), "sequence", 1), c.user)
    |> Ecto.Changeset.put_change(:parent_id, row("boxA").id)
    |> Repo.insert!()

    assert tree(c.page) != saved

    load_and_save(c, revision)
    await(fn -> tree(c.page) == saved end)

    gone = row("gone")
    assert body("gone") == "Deleted since"
    assert {gone.sync_uid, gone.module_version} == {"gone-sync", 2}
  end

  test "a child moved out of a nested container goes back into it", c do
    roots!(c, [
      container(c, "boxA", [
        module_block(c, "keepA", "Stays in A"),
        container(c, "inner", [module_block(c, "nested", "In the inner container")])
      ]),
      container(c, "boxB", [module_block(c, "keepB", "Stays in B")])
    ])

    stamp!("nested", sync_uid: "nested-sync", module_version: 5)
    revision = revision!(c)
    saved = tree(c.page)

    move!(c, "nested", "boxB", 1, "Moved on")
    assert tree(c.page) != saved

    load_and_save(c, revision)
    await(fn -> tree(c.page) == saved end)

    nested = row("nested")
    assert body("nested") == "In the inner container"
    assert {nested.parent.uid, nested.sync_uid, nested.module_version} == {"inner", "nested-sync", 5}
  end
end
