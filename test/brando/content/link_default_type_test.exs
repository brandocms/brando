defmodule Brando.Content.LinkDefaultTypeTest do
  # A link var's default tab (`link_default_type`) is where its dialog opens
  # while the link is empty: copies from the module start there, and a changed
  # default moves the empty vars of existing blocks and of the var itself.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content
  alias Brando.Content.Blocks
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Repo

  setup do
    {:ok, user: Factory.insert(:random_user)}
  end

  defp link_var(key, attrs \\ []) do
    struct(%Var{type: :link, key: key, label: %{"en" => key}, link_type: :url, sequence: 0}, attrs)
  end

  defp module_with(vars), do: :module |> Factory.insert(vars: vars) |> Brando.Cache.Query.evict()

  defp link_types(vars), do: Map.new(vars, &{&1.key, &1.link_type})

  defp page_with_block(module, user) do
    block =
      module.id
      |> Blocks.build_module_block(user.id, nil, Page.Blocks, :module)
      |> Ecto.Changeset.apply_changes()

    vars = Enum.map(block.vars, &Map.take(&1, [:type, :key, :label, :value, :link_type, :link_default_type, :sequence]))
    block_params = %{uid: block.uid, type: :module, module_id: module.id, source: Page.Blocks, vars: vars}
    params = Factory.params_for(:page, vars: [], entry_blocks: [%{sequence: 0, block: block_params}])
    {:ok, page} = %Page{} |> Page.changeset(params, user, nil, cast_blocks: true) |> Repo.insert()
    page
  end

  defp block_vars(page) do
    Repo.all(
      from(v in Var,
        join: b in assoc(v, :block),
        join: j in Page.Blocks,
        on: j.block_id == b.id,
        where: j.entry_id == ^page.id
      )
    )
  end

  test "a new block's empty link var opens on its default tab", %{user: user} do
    module =
      module_with([
        link_var("entry", link_default_type: :identifier),
        link_var("set", link_default_type: :identifier, value: "https://example.com", sequence: 1),
        link_var("plain", sequence: 2)
      ])

    block =
      module.id
      |> Blocks.build_module_block(user.id, nil, Page.Blocks, :module)
      |> Ecto.Changeset.apply_changes()

    assert link_types(block.vars) == %{"entry" => :identifier, "set" => :url, "plain" => :url}
  end

  test "a var added to an imported block or a recovery copy opens on its default tab" do
    module = module_with([link_var("entry", link_default_type: :identifier)])

    params = Brando.Content.Transfer.Contracts.defaults(%{"refs" => [], "vars" => []}, module)
    assert [%{"link_type" => "identifier"}] = params["vars"]

    fields = %{"blocks" => [%{"uid" => "draft-block", "module_id" => module.id, "refs" => [], "vars" => []}]}

    assert {%{"blocks" => [recovered]}, []} =
             Brando.Drafts.Modules.check(fields, Brando.Drafts.Modules.manifest(fields))

    assert [%{"link_type" => "identifier"}] = recovered["vars"]
  end

  test "saving a module with a new default moves the empty vars of its blocks", %{user: user} do
    module = module_with([link_var("empty"), link_var("set", sequence: 1)])
    page = page_with_block(module, user)

    [set_var] = page |> block_vars() |> Enum.filter(&(&1.key == "set"))
    set_var |> Ecto.Changeset.change(value: "https://example.com") |> Repo.update!()

    module = Repo.preload(module, :vars, force: true)
    vars = Enum.map(module.vars, &%{id: &1.id, key: &1.key, link_default_type: :identifier})
    assert {:ok, _} = Content.update_module(module, %{vars: vars}, user)

    stored = block_vars(page)
    assert link_types(stored) == %{"empty" => :identifier, "set" => :url}
    assert Enum.all?(stored, &(&1.link_default_type == :identifier))
  end

  describe "a var saved with a new default" do
    setup %{user: user} do
      {:ok, page} = Pages.create_page(Factory.params_for(:page, vars: [%{type: :link, key: "cta", label: %{"en" => "Cta"}}]), user)
      {:ok, page: Repo.preload(page, :vars)}
    end

    defp save_var(page, attrs, user) do
      [var] = page.vars
      {:ok, page} = page |> Page.changeset(%{vars: [Map.merge(%{id: var.id}, attrs)]}, user) |> Repo.update()
      page |> Repo.preload(:vars, force: true) |> Map.fetch!(:vars) |> hd()
    end

    test "opens on it while empty", %{page: page, user: user} do
      assert %{link_default_type: :identifier, link_type: :identifier} =
               save_var(page, %{link_default_type: :identifier}, user)
    end

    test "keeps a link that is set", %{page: page, user: user} do
      assert %{link_default_type: :identifier, link_type: :url} =
               save_var(page, %{link_default_type: :identifier, value: "https://example.com"}, user)
    end

    test "leaves the tab to the editor until it is saved", %{page: page} do
      [var] = page.vars
      params = %{"link_default_type" => "identifier", "link_type" => "url"}
      changeset = Var.changeset(var, params, %{id: var.creator_id})

      assert Ecto.Changeset.get_field(changeset, :link_type) == :url
    end
  end
end
