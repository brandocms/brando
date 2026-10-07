defmodule Brando.Content.StartingModulesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Content.Block
  alias Brando.Content.StartingModules
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker

  setup do
    user = Factory.insert(:random_user)
    Brando.Cache.del(StartingModules.cache_key(Page.Blocks, "en"))
    Brando.Cache.del(StartingModules.cache_key(Page.Blocks, "no"))
    Brando.Cache.del(StartingModules.cache_key(Page.Blocks, nil))

    modules =
      for {class, sequence} <- Enum.with_index(~w(hero intro text image)) do
        {:ok, module} =
          Content.create_module(
            Factory.params_for(:module,
              name: %{"en" => String.capitalize(class)},
              namespace: %{"en" => "Starting"},
              help_text: %{},
              class: class,
              sequence: sequence
            ),
            user
          )

        {String.to_atom(class), module}
      end

    {:ok, section} =
      Content.create_container(%{name: "Section", namespace: "general", code: "{{ content }}"}, user)

    Map.merge(Map.new(modules), %{user: user, modules: Keyword.values(modules), section: section})
  end

  # A page whose root blocks are `roots`, in order: a module, or a
  # `{container, [module]}`.
  defp page!(roots, attrs \\ []) do
    page = Factory.insert(:page, Keyword.merge([language: :en], attrs))

    roots
    |> Enum.with_index()
    |> Enum.each(fn {root, sequence} ->
      Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: root_block!(root).id, sequence: sequence})
    end)

    page
  end

  defp root_block!({container, children}) do
    parent = block!(type: :container, container_id: container.id)

    children
    |> Enum.with_index()
    |> Enum.each(fn {module, sequence} -> block!(module_id: module.id, parent_id: parent.id, sequence: sequence) end)

    parent
  end

  defp root_block!(module), do: block!(module_id: module.id)

  defp block!(attrs) do
    Repo.insert!(struct(%Block{type: :module, source: Page.Blocks, uid: Brando.Utils.generate_uid()}, attrs))
  end

  defp tiles(c, opts \\ []) do
    StartingModules.list(Page.Blocks, Keyword.get(opts, :modules, c.modules), Keyword.put_new(opts, :language, "en"))
  end

  defp summary(tiles), do: Enum.map(tiles, &{&1.module.class, &1.container && &1.container.name, &1.count, &1.of})

  test "modules are ranked by how often they come first, and overall use only fills", c do
    for _ <- 1..3, do: page!([c.hero, c.text, c.text])
    for _ <- 1..2, do: page!([c.intro, c.text, c.image])
    page!([c.text, c.image])

    # Text is used most (9 times) but comes first once; image never comes
    # first and fills the last slot without a count.
    assert summary(tiles(c)) == [
             {"hero", nil, 3, 6},
             {"intro", nil, 2, 6},
             {"text", nil, 1, 6},
             {"image", nil, nil, nil}
           ]

    assert [%{module_ref: "local:" <> _, container_ref: nil} | _] = tiles(c)
    assert Enum.map(tiles(c), & &1.source) == [:first, :first, :first, :used]
  end

  test "a container that comes first is counted with its first module", c do
    for _ <- 1..3, do: page!([{c.section, [c.hero, c.text]}, c.text])
    for _ <- 1..2, do: page!([c.intro])

    assert [first, second | _] = tiles(c)
    assert {"hero", "Section", 3, 5} == hd(summary([first]))
    assert first.container_ref == "local:#{c.section.id}"
    assert {"intro", nil, 2, 5} == hd(summary([second]))
  end

  test "with fewer than five entries the modules keep their own order, without counts", c do
    for _ <- 1..4, do: page!([c.image])

    assert summary(tiles(c)) == [
             {"hero", nil, nil, nil},
             {"intro", nil, nil, nil},
             {"text", nil, nil, nil},
             {"image", nil, nil, nil}
           ]
  end

  test "starts_with pins modules to the front", c do
    for _ <- 1..5, do: page!([c.hero])

    assert summary(tiles(c, starts_with: ["image", :text])) == [
             {"image", nil, nil, nil},
             {"text", nil, nil, nil},
             {"hero", nil, 5, 5},
             {"intro", nil, nil, nil}
           ]

    assert Enum.map(tiles(c, starts_with: ["image", :text]), & &1.source) == [:order, :order, :first, :order]

    # A pinned module keeps its count when it does come first.
    assert [{"hero", nil, 5, 5} | _] = summary(tiles(c, starts_with: ["hero"]))
    # Unknown classes are ignored.
    assert [{"hero", nil, 5, 5} | _] = summary(tiles(c, starts_with: ["nothing"]))
  end

  test "only entries in the language are counted", c do
    for _ <- 1..5, do: page!([c.intro], language: :no)
    page!([c.hero])

    assert %{entries: 1} = StartingModules.count(Page.Blocks, :en)
    assert %{entries: 5, first: [{{{:local, id}, nil}, 5}]} = StartingModules.count(Page.Blocks, "no")
    assert id == c.intro.id

    assert [{"intro", nil, 5, 5} | _] = summary(tiles(c, language: "no"))
    assert [{"hero", nil, nil, nil} | _] = summary(tiles(c, language: "en"))
  end

  test "soft deleted entries are not counted", c do
    pages = for _ <- 1..5, do: page!([c.intro])
    assert %{entries: 5} = StartingModules.count(Page.Blocks, :en)

    Repo.update!(Ecto.Changeset.change(hd(pages), deleted_at: DateTime.truncate(DateTime.utc_now(), :second)))
    assert %{entries: 4} = StartingModules.count(Page.Blocks, :en)
  end

  test "only the modules offered are shown", c do
    for _ <- 1..5, do: page!([c.hero, c.intro])

    offered = [c.intro, c.text]
    assert summary(tiles(c, modules: offered)) == [{"intro", nil, nil, nil}, {"text", nil, nil, nil}]

    # The picker's root modules leave out a deleted module.
    assert Enum.any?(ModulePicker.root_modules("all"), &(&1.id == c.hero.id))
    {:ok, _} = Content.delete_module(c.hero.id, c.user)
    refute Enum.any?(ModulePicker.root_modules("all"), &(&1.id == c.hero.id))
  end

  test "a field's counts are cached per site, field and language", c do
    assert StartingModules.cache_key(Page.Blocks, :en) == {:starting_modules, Page.Blocks, "en"}
    assert StartingModules.cache_key(Page.Blocks, "en") == StartingModules.cache_key(Page.Blocks, :en)
    refute StartingModules.cache_key(Page.Blocks, "no") == StartingModules.cache_key(Page.Blocks, "en")
    refute StartingModules.cache_key(Page.Blocks, "en") == StartingModules.cache_key(Brando.Pages.Fragment.Blocks, "en")

    assert Brando.Tenant.cache_key(StartingModules.cache_key(Page.Blocks, "en"), "tenant_a_b") ==
             {:tenant, "tenant_a_b", {:starting_modules, Page.Blocks, "en"}}

    assert %{entries: 0} = StartingModules.counts(Page.Blocks, "en")
    page!([c.hero])
    assert %{entries: 0} = StartingModules.counts(Page.Blocks, "en")

    Brando.Cache.del(StartingModules.cache_key(Page.Blocks, "en"))
    assert %{entries: 1} = StartingModules.counts(Page.Blocks, "en")
  end
end
