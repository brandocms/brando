defmodule Brando.Content.TrashedModuleWrittenTest do
  # A revision restore, a scheduled revision and a duplicate do not bring a
  # module in the trash back into use (#3923): each is refused, naming the
  # module and the block, and writes nothing. A revision that only keeps a
  # block the entry holds now is restored, as an in-place save is.
  use Brando.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Revisions
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleAuthorLink

  setup do
    user = Factory.insert(:random_user)
    module = Factory.insert(:module, name: %{"en" => "Teaser"}, code: "<p>teaser</p>", vars: [], refs: [])
    %{user: user, module: module}
  end

  describe "restoring a revision" do
    # The root is removed: its join row goes, its rows stay for the
    # revision, and nothing uses the module any longer, so it can be
    # trashed. The restore would join the root again.
    setup c do
      container = container!(c.user)
      root =
        Map.merge(rows(), %{
          type: :container,
          container_id: container.id,
          uid: uid(),
          source: source(),
          children: [block(c.module)]
        })
      page = page!(c.user, [root])
      [%{block_id: root_id}] = loaded(page).entry_blocks
      {:ok, page} = page |> loaded() |> Page.changeset(%{title: "Emptied"}, c.user) |> put_roots([]) |> update(c.user)
      trash!(c.module)

      %{page: page, root_id: root_id}
    end

    test "that would bring back a detached block of a module in the trash is refused by name", c do
      assert Repo.get(Block, c.root_id)
      active = active_revision(c.page)

      assert {:error, {:module_in_trash, %{module: %{"en" => "Teaser"}, block: {:inside, {:root, 1}}}}} =
               Revisions.set_entry_to_revision(Page, c.page.id, 0, c.user)

      assert roots(c.page) == []
      assert Repo.get!(Page, c.page.id).title == "Emptied"
      assert active_revision(c.page) == active
    end

    test "that is refused leaves a schedule it would have set aside as it was", c do
      publish_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      {:ok, job} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Brando.Publisher.schedule_revision(Page, c.page.id, 0, publish_at, c.user)
        end)

      assert {:error, {:module_in_trash, _}} =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 Revisions.set_entry_to_revision(Page, c.page.id, 0, c.user)
               end)

      assert Repo.get!(Oban.Job, job.id).state == "scheduled"
      assert scheduled?(c.page, 0)
    end

    test "goes once the module is restored", c do
      {:ok, _} = Brando.Authorization.Boundary.restore(:system, Repo.get!(Brando.Content.Module, c.module.id))

      assert {:ok, _} = Revisions.set_entry_to_revision(Page, c.page.id, 0, c.user)
      assert [_root] = roots(c.page)
    end
  end

  test "a revision that keeps a block the entry holds of a module in the trash is restored", c do
    page = page!(c.user, [block(c.module)])
    {:ok, _} = Pages.update_page(page.id, %{title: "Changed since"}, c.user)
    trash_in_use!(c.module)

    assert {:ok, restored} = Revisions.set_entry_to_revision(Page, page.id, 0, c.user)
    assert restored.title == page.title
    assert [%{block: %{module_id: module_id}}] = loaded(page).entry_blocks
    assert module_id == c.module.id
  end

  describe "a scheduled revision that would bring back such a block" do
    setup c do
      page = page!(c.user, [block(c.module)])
      {:ok, page} = page |> loaded() |> Page.changeset(%{title: "Emptied"}, c.user) |> put_roots([]) |> update(c.user)
      trash!(c.module)
      %{page: page}
    end

    test "is cancelled at once, its schedule dropped, with one Activity line naming the module and the block", c do
      publish_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      {:ok, job} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Brando.Publisher.schedule_revision(Page, c.page.id, 0, publish_at, c.user)
        end)

      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [scheduled_at: DateTime.utc_now()])

      assert %{cancelled: 1} =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 Oban.drain_queue(queue: :default, with_scheduled: true)
               end)

      assert %{state: "cancelled", attempt: 1} = Repo.get!(Oban.Job, job.id)
      refute scheduled?(c.page, 0)
      assert Repo.get!(Page, c.page.id).title == "Emptied"
      assert roots(c.page) == []

      assert [%{revision: 0, details: %{"scheduled_revision" => refused}}] = scheduled_activity(c.page)
      assert %{"reason" => "module_in_trash", "module" => %{"en" => "Teaser"}, "block" => block} = refused
      assert Brando.Activity.decode_place(block) == {:root, 1}
    end

    # The job's cleanup runs after the refusal released the lock: by then
    # the revision may have another job
    test "leaves a schedule made since alone", c do
      Revisions.mark_revision_scheduled(Page, c.page.id, 0, true)
      refusal = %{module: %{"en" => "Teaser"}, block: {:root, 1}}

      assert :ok = Revisions.drop_schedule_with_trashed_module(Page, c.page.id, 0, c.user, refusal, fn -> false end)
      assert scheduled?(c.page, 0)
      assert scheduled_activity(c.page) == []
    end
  end

  # A revision stored before blocks had a module version, written over
  # blocks that have one: a block in place and one moved since, which the
  # restore inserts again under its old row's stamp. Each holds a ref its
  # module has retired since; another module only moved on.
  describe "the module version of the blocks a revision restores" do
    test "is their module's, or behind it while they hold a ref it retired", c do
      kept = module!(c.user, "Kept", ["body"])
      retired = module!(c.user, "Retired", ["body", "text"])
      container = container!(c.user)
      page = Factory.insert(:page, creator: c.user)

      insert_root!(page, 0, c.user, %{
        "uid" => "box-a",
        "type" => "container",
        "container_id" => container.id,
        "children" => [module_params(c.user, "moved", retired, "Old moved")]
      })

      insert_root!(page, 1, c.user, %{"uid" => "box-b", "type" => "container", "container_id" => container.id})
      insert_root!(page, 2, c.user, module_params(c.user, "kept", kept, "Old kept"))
      insert_root!(page, 3, c.user, module_params(c.user, "in-place", retired, "Old in place"))
      stamp!("moved", sync_uid: "moved-sync")

      {:ok, revision} = Revisions.create_revision(page, c.user)
      :ok = Brando.OldRevisions.forget_block_identity!(page, revision.revision)

      # since: both modules moved on, one retiring `body`; the blocks were
      # synced and resolved, and one moved to the other box as a new row
      for module <- [kept, retired], do: Repo.update_all(module_query(module), set: [version: 2])
      Repo.delete_all(from(r in Brando.Content.Ref, where: r.module_id == ^retired.id and r.name == "body"))

      Repo.delete!(row("moved"))
      moved = Repo.insert!(%Block{uid: "moved", type: :module, module_id: retired.id, source: source()})
      stamp!("moved", parent_id: row("box-b").id, sync_uid: "moved-sync")

      for uid <- ["moved", "in-place"] do
        Repo.delete_all(from(r in Brando.Content.Ref, where: r.block_id == ^row(uid).id and r.name == "body"))
      end

      for uid <- ["moved", "kept", "in-place"], do: stamp!(uid, module_version: 2)

      assert {:ok, restored} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, c.user)

      # as whoever has the entry open gets it
      returned = Map.new(restored.entry_blocks, &{&1.block.uid, &1.block.module_version})
      assert returned["kept"] == row("kept").module_version
      assert returned["in-place"] == row("in-place").module_version

      for {uid, module} <- [{"moved", retired}, {"kept", kept}, {"in-place", retired}] do
        module = Repo.get!(Brando.Content.Module, module.id)
        block = row(uid)
        assert block.module_version == module.version or block.id in Brando.Content.Blocks.list_stale_block_ids(module)
      end

      assert row("kept").module_version == 2
      stale = Brando.Content.Blocks.list_stale_block_ids(retired.id)

      for uid <- ["moved", "in-place"] do
        assert row(uid).id in stale
        assert body(uid) =~ "Old"
      end

      moved_back = row("moved")
      assert moved_back.id != moved.id
      assert moved_back.parent_id == row("box-a").id
      assert moved_back.sync_uid == "moved-sync"
    end
  end

  describe "duplicating an entry" do
    test "holding a block of a module in the trash is refused by name, and copies nothing", c do
      page = page!(c.user, [Map.put(block(c.module), :description, "Front teaser")])
      trash_in_use!(c.module)
      pages = Repo.aggregate(Page, :count)

      assert {:error, {:module_in_trash, %{module: %{"en" => "Teaser"}, block: {:described, "Front teaser"}} = refusal}} =
               Pages.duplicate_page(page.id, c.user)

      assert Repo.aggregate(Page, :count) == pages
      assert Brando.Content.module_in_trash_message(refusal, :duplicate) =~ "Front teaser"
    end

    test "is refused for a block of a subform row it owns, and clones no gallery", c do
      source = article_with_link_block!(c)
      trash_in_use!(c.module)
      articles = Repo.aggregate(Article, :count)
      galleries = Repo.aggregate(Brando.Galleries.Gallery, :count)

      assert {:error, {:module_in_trash, %{module: %{"en" => "Teaser"}}}} =
               SyncTest.duplicate_article(source.id, c.user, change_fields: [slug: "copy"])

      assert Repo.aggregate(Article, :count) == articles
      assert Repo.aggregate(Brando.Galleries.Gallery, :count) == galleries
    end

    test "is refused for a module trashed after the source was read", c do
      page = page!(c.user, [block(c.module)])
      trash = fn _entry, title -> tap(title, fn _ -> trash_in_use!(c.module) end) end

      assert {:error, {:module_in_trash, %{module: %{"en" => "Teaser"}}}} =
               Pages.duplicate_page(page.id, c.user, change_fields: [title: trash])
    end

    test "goes with the module live", c do
      page = page!(c.user, [block(c.module)])
      assert {:ok, copy} = Pages.duplicate_page(page.id, c.user)
      assert [%{block: %{module_id: module_id}}] = loaded(copy).entry_blocks
      assert module_id == c.module.id
    end
  end

  # A subform row's block, and a gallery the row holds
  defp article_with_link_block!(c) do
    {:ok, source} =
      SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published"}, c.user)

    image = Factory.insert(:image, creator_id: c.user.id)
    gallery = Factory.insert(:gallery, gallery_objects: [Factory.build(:gallery_object, image: image, creator: c.user)])

    author =
      Repo.insert!(%SyncTest.ArticleAuthor{
        article_id: source.id,
        name: "Example Author",
        links: [%ArticleAuthorLink{label: "Example Hotel", gallery_id: gallery.id}]
      })

    block =
      Repo.insert!(%Block{
        uid: uid(),
        type: :module,
        module_id: c.module.id,
        source: to_string(ArticleAuthorLink.Blocks)
      })

    Repo.insert!(%ArticleAuthorLink.Blocks{entry_id: hd(author.links).id, block_id: block.id, sequence: 0})
    source
  end

  defp module!(user, name, ref_names) do
    refs = for name <- ref_names, do: %{name: name, uid: uid(), data: %{type: "text", data: %{text: "Default"}}}

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => name},
          help_text: %{},
          code: Enum.map_join(ref_names, &"{% ref refs.#{&1} %}"),
          refs: refs,
          vars: []
        ),
        user
      )

    module
  end

  defp module_query(module), do: from(m in Brando.Content.Module, where: m.id == ^module.id)

  defp module_params(user, uid, module, text) do
    refs =
      for {%{name: name}, n} <- module |> Repo.preload(:refs) |> Map.fetch!(:refs) |> Enum.with_index(),
          do: %{"uid" => uid(), "name" => name, "sequence" => n, "data" => %{"type" => "text", "data" => %{"text" => text}}}

    %{"uid" => uid, "type" => "module", "module_id" => module.id, "creator_id" => user.id, "refs" => refs}
  end

  defp insert_root!(page, sequence, user, params) do
    params = Map.put(params, "source", source())

    params =
      Map.update(params, "children", [], fn children ->
        children |> Enum.with_index() |> Enum.map(fn {child, n} -> Map.merge(child, %{"source" => source(), "sequence" => n}) end)
      end)

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()
    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: sequence})
  end

  defp row(uid), do: Repo.get_by!(Block, uid: uid)

  defp stamp!(uid, fields), do: Repo.update_all(from(b in Block, where: b.uid == ^uid), set: fields)

  defp body(uid) do
    [ref] = Repo.all(from(r in Brando.Content.Ref, where: r.block_id == ^row(uid).id and r.name == "body"))
    ref.data.data.text
  end

  # In the trash as the delete puts it there
  defp trash!(module) do
    {:ok, trashed} = Brando.Content.delete_module(module.id, :system)
    trashed
  end

  # As a site has it from before the delete checked for uses
  defp trash_in_use!(module), do: Repo.soft_delete!(module)

  defp container!(user) do
    {:ok, container} =
      Brando.Content.create_container(%{name: "Section", namespace: "general", code: "{{ content }}"}, user)

    container
  end

  defp uid, do: "block-#{System.unique_integer([:positive])}"
  defp source, do: "Elixir.Brando.Pages.Page.Blocks"

  defp block(module), do: Map.merge(rows(), %{type: :module, module_id: module.id, source: source(), uid: uid()})

  # As a form saves a block, so its revision holds them
  defp rows, do: %{refs: [], vars: [], table_rows: [], block_identifiers: [], children: []}

  defp page!(user, roots) do
    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> put_roots(roots)
      |> Map.put(:action, :insert)

    {:ok, page} = Pages.create_page(changeset, user)
    page
  end

  defp put_roots(changeset, roots), do: Ecto.Changeset.put_assoc(changeset, :entry_blocks, Enum.map(roots, &%{block: &1}))

  defp update(changeset, user), do: Pages.update_page(changeset, user)

  defp loaded(page) do
    Page
    |> Repo.get!(page.id)
    |> Repo.preload(Brando.Content.BlockPreloads.for_schema(Page), force: true)
  end

  defp roots(page), do: Repo.all(from(j in Page.Blocks, where: j.entry_id == ^page.id))

  defp active_revision(page) do
    {:ok, revisions} = Revisions.list_revision_metadata(Page, page.id)
    Enum.find(revisions, & &1.active).revision
  end

  defp scheduled?(page, revision) do
    {:ok, revisions} = Revisions.list_revision_metadata(Page, page.id)
    Enum.find(revisions, &(&1.revision == revision)).scheduled
  end

  defp scheduled_activity(page),
    do: Page |> Brando.Activity.for_entry(page.id) |> Enum.filter(&(&1.details["scheduled_revision"] != nil))
end
