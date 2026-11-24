defmodule Brando.Content.TrashedModuleInUseTest do
  # A module in the trash does not come back into use (#3902): a save that
  # adds one of its blocks, and a restore of an entry holding one, are
  # refused by the module's name. Blocks an entry held before do not stop
  # its saves.
  use Brando.ConnCase, async: true

  alias Brando.Authorization.Boundary
  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page

  setup do
    user = Factory.insert(:random_user)
    module = Factory.insert(:module, name: %{"en" => "Teaser"}, code: "<p>teaser</p>", vars: [], refs: [])
    %{user: user, module: module}
  end

  describe "a save that adds a block of a module in the trash" do
    test "is refused for a new entry, naming the module and the block, and saves nothing", c do
      trash!(c.module)
      pages = page_count()

      changeset =
        %Page{}
        |> Page.changeset(Factory.params_for(:page), c.user)
        |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block(c.module)}])
        |> Map.put(:action, :insert)

      assert {:error, {:module_in_trash, %{module: %{"en" => "Teaser"}, block: {:root, 1}}}} =
               Pages.create_page(changeset, c.user)

      assert page_count() == pages
    end

    test "is refused when it adds one to a saved entry, which keeps its blocks", c do
      other = Factory.insert(:module, vars: [], refs: [])
      page = page!(c.user, [block(other)])
      trash!(c.module)

      changeset = add_roots(page, c.user, [block(c.module)])

      assert {:error, {:module_in_trash, %{block: {:root, 2}}}} = Pages.update_page(changeset, c.user)
      assert [%{module_id: other_id}] = blocks(page)
      assert other_id == other.id
    end

    test "names the block by its description", c do
      page = page!(c.user, [])
      trash!(c.module)

      changeset = add_roots(page, c.user, [Map.put(block(c.module), :description, "Front teaser")])

      assert {:error, {:module_in_trash, %{block: {:described, "Front teaser"}} = refusal}} =
               Pages.update_page(changeset, c.user)

      assert Brando.Content.module_in_trash_message(refusal) =~ "Front teaser"
      assert Brando.Content.module_in_trash_message(refusal) =~ "Teaser"
    end

    # The entry holds one already: a second, under its container, is refused,
    # and without it the save goes through
    test "counts a new block under a saved root, though the entry holds one of the module", c do
      container = container!(c.user)
      root = %{type: :container, container_id: container.id, uid: uid(), source: source(), children: [block(c.module)]}
      page = page!(c.user, [root])
      trash_in_use!(c.module)

      [%{block: saved_root} = entry_block] = loaded(page).entry_blocks
      [saved_child] = saved_root.children

      duplicate = %{
        "type" => "module",
        "module_id" => to_string(c.module.id),
        "uid" => uid(),
        "source" => source(),
        "sequence" => "1"
      }

      with_duplicate = children_save(page, c.user, entry_block, [%{"id" => to_string(saved_child.id)}, duplicate])

      assert {:error, {:module_in_trash, %{block: {:inside, {:root, 1}}}}} = Pages.update_page(with_duplicate, c.user)
      assert length(blocks(page)) == 2

      without = children_save(page, c.user, entry_block, [%{"id" => to_string(saved_child.id)}], %{title: "Kept"})
      assert {:ok, %{title: "Kept"}} = Pages.update_page(without, c.user)
      assert length(blocks(page)) == 2
    end
  end

  test "an entry holding a block of a module in the trash still saves", c do
    page = page!(c.user, [block(c.module)])
    trash_in_use!(c.module)

    changeset = page |> loaded() |> Page.changeset(%{title: "Edited"}, c.user)

    assert {:ok, %{title: "Edited"}} = Pages.update_page(changeset, c.user)
  end

  describe "restoring an entry from the trash" do
    test "is refused while it holds a block of a module in the trash, which it names", c do
      page = page!(c.user, [block(c.module)])
      {:ok, trashed} = Pages.delete_page(page.id, c.user)
      trash!(c.module)

      assert {:error, {:module_in_trash, %{module: %{"en" => "Teaser"}} = refusal}} = Boundary.restore(c.user, trashed)
      refute Map.has_key?(refusal, :block)
      assert %{deleted_at: %DateTime{}} = Repo.get!(Page, page.id)
    end

    test "goes once the module is restored", c do
      page = page!(c.user, [block(c.module)])
      {:ok, trashed} = Pages.delete_page(page.id, c.user)
      trashed_module = trash!(c.module)

      {:ok, _} = Boundary.restore(c.user, trashed_module)
      assert {:ok, %{deleted_at: nil}} = Boundary.restore(c.user, trashed)
    end

    test "is refused for :system too", c do
      page = page!(c.user, [block(c.module)])
      {:ok, trashed} = Pages.delete_page(page.id, c.user)
      trash!(c.module)

      assert {:error, {:module_in_trash, _}} = Boundary.restore(:system, trashed)
    end

    test "of a fragment counts its nested blocks", c do
      fragment = Factory.insert(:fragment, creator: c.user, key: "nested")
      container = container!(c.user)
      root = put_block!(Fragment, fragment, %{type: :container, container_id: container.id})
      child_block!(root, c.module)
      {:ok, trashed} = Pages.delete_fragment(fragment.id, c.user)
      trash!(c.module)

      assert {:error, {:module_in_trash, _}} = Boundary.restore(c.user, trashed)
    end

    # The page's restore brings back its fragments: the whole set is checked,
    # and nothing comes back
    test "of a page is refused for a block in a fragment trashed with it", c do
      page = page!(c.user, [])
      first = Factory.insert(:fragment, creator: c.user, page_id: page.id, key: "first")
      second = Factory.insert(:fragment, creator: c.user, page_id: page.id, key: "second")
      put_block!(Fragment, second, %{type: :module, module_id: c.module.id})

      {:ok, trashed} = Pages.delete_page(page.id, c.user, fragments: :delete)
      trash!(c.module)

      assert {:error, {:module_in_trash, %{module: %{"en" => "Teaser"}}}} = Boundary.restore(c.user, trashed)

      for {schema, id} <- [{Page, page.id}, {Fragment, first.id}, {Fragment, second.id}],
          do: assert(%{deleted_at: %DateTime{}} = Repo.get!(schema, id))
    end
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

  defp block(module), do: %{type: :module, module_id: module.id, source: source(), uid: uid()}

  defp page!(user, roots) do
    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, Enum.map(roots, &%{block: &1}))
      |> Map.put(:action, :insert)

    {:ok, page} = Pages.create_page(changeset, user)
    page
  end

  defp loaded(page) do
    Page
    |> Repo.get!(page.id)
    |> Repo.preload(Brando.Content.BlockPreloads.for_schema(Page), force: true)
  end

  # The saved roots as the form sends them, by id, then `roots`
  defp add_roots(page, user, roots) do
    page = loaded(page)

    saved =
      Enum.map(
        page.entry_blocks,
        &Page.Blocks.changeset(&1, %{"block" => %{"id" => to_string(&1.block.id)}}, user.id, true)
      )

    page
    |> Page.changeset(%{}, user)
    |> Ecto.Changeset.put_assoc(:entry_blocks, saved ++ Enum.map(roots, &%{block: &1}))
  end

  # A save of the page's one root with `children` as the form sends them
  defp children_save(page, user, entry_block, children, params \\ %{}) do
    root =
      Page.Blocks.changeset(
        entry_block,
        %{"block" => %{"id" => to_string(entry_block.block.id), "children" => children}},
        user.id,
        true
      )

    page
    |> loaded()
    |> Page.changeset(params, user)
    |> Ecto.Changeset.put_assoc(:entry_blocks, [root])
  end

  # A block saved before the check: written past the save
  defp put_block!(schema, entry, attrs) do
    block = Repo.insert!(struct(Block, Map.merge(%{uid: uid(), source: "Elixir.#{inspect(schema)}.Blocks"}, attrs)))
    Repo.insert_all(Module.concat(schema, "Blocks"), [%{entry_id: entry.id, block_id: block.id, sequence: 0}])
    block
  end

  defp child_block!(parent, module),
    do: Repo.insert!(%Block{uid: uid(), source: parent.source, type: :module, module_id: module.id, parent_id: parent.id})

  defp blocks(page) do
    page |> loaded() |> Map.fetch!(:entry_blocks) |> Enum.flat_map(&[&1.block | &1.block.children])
  end

  defp page_count, do: Repo.aggregate(Page, :count)
end
