defmodule Brando.Content.LibraryOverrideSaveRendersTest do
  # A site's override of a shared-library module, container or palette stands
  # in under the library entry's id, which the site's blocks hold with origin
  # `:shared` (`Brando.Content.SharedLibrary`). Saving the override in the
  # admin renders the entries whose blocks use it.
  #
  # The library entry and the override share one schema here: the save picks
  # the blocks by id and origin alone.
  use Brando.ConnCase, async: false

  alias Brando.Content.Container
  alias Brando.Content.Module
  alias Brando.Content.Palette
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo

  setup do
    %{user: Factory.insert(:random_user)}
  end

  test "a module override's save queues the render of a page whose block uses the library module", c do
    library = Factory.insert(:module, code: "<p>library</p>")
    override = Factory.insert(:module, code: "<p>site</p>", source_module_id: library.id)
    page = page!(c.user, %{type: :module, module_id: library.id, module_origin: :shared})

    assert_save_queues_render(page, fn ->
      changeset = Module.changeset(override, %{"code" => "<p>site v2</p>"}, c.user)
      Brando.Content.update_module(changeset, c.user)
    end)
  end

  test "a container override's save queues the render of a page whose block uses the library container", c do
    library = container!("Library section", nil)
    override = container!("Site section", library.id)
    module = Factory.insert(:module, code: "<p>inside</p>")

    page =
      page!(c.user, %{
        type: :container,
        container_id: library.id,
        container_origin: :shared,
        children: [%{type: :module, module_id: module.id, source: source(), uid: uid()}]
      })

    assert_save_queues_render(page, fn ->
      changeset = Container.changeset(override, %{"code" => "<div>{{ content }}</div>"}, c.user)
      Brando.Content.update_container(changeset, c.user)
    end)
  end

  test "a palette override's save queues the render of a page whose block uses the library palette", c do
    library = Factory.insert(:palette, key: "library", status: :published)
    override = Factory.insert(:palette, key: "site", status: :published, source_palette_id: library.id)
    module = Factory.insert(:module, code: "<p>coloured</p>")
    page = page!(c.user, %{type: :module, module_id: module.id, palette_id: library.id, palette_origin: :shared})

    assert_save_queues_render(page, fn ->
      changeset = Palette.changeset(override, %{"instructions" => "Darker"}, c.user)
      Brando.Content.update_palette(changeset, c.user)
    end)
  end

  defp assert_save_queues_render(page, save) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} = save.()
      assert [_job] = all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: page.id})
    end)
  end

  defp container!(name, source_container_id) do
    Repo.insert!(%Container{
      uid: uid(),
      name: name,
      namespace: "Sections",
      code: "<section>{{ content }}</section>",
      source_container_id: source_container_id
    })
  end

  defp page!(user, block) do
    blocks = [%{block: Map.merge(%{source: source(), uid: uid()}, block)}]

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, blocks)
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    page
  end

  defp source, do: "Elixir.Brando.Pages.Page.Blocks"
  defp uid, do: "block-#{System.unique_integer([:positive])}"
end
