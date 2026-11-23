defmodule Brando.Content.ContainerPaletteChangesRenderTest do
  # Deleting a container or saving a palette renders again the entries whose
  # blocks use it (#3861). With Villain's production query caching on, so a
  # render reads the cached containers and palettes.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [preserve_cache: 1]

  alias Brando.Content.Palette
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Villain.RenderSourceQuery

  setup do
    Application.put_env(:brando, :villain_query_cache, true)
    Cachex.clear(:query)

    on_exit(fn ->
      Application.delete_env(:brando, :villain_query_cache)
      Cachex.clear(:query)
    end)

    preserve_cache([:palettes, :palettes_css])
    user = Factory.insert(:random_user)
    paper = palette!(user)
    %{user: user, paper: paper, container: container!(user, paper)}
  end

  describe "deleting a container" do
    test "queues the render of a page using it, which prints the blocks without it", c do
      page = page!(c.user, %{type: :container, container_id: c.container.id, children: [inside()]})
      assert rendered(page) =~ ~s(<section class="v1"><p>inside</p></section>)

      job = queues_render(page, fn -> Brando.Content.delete_container(c.container.id, c.user) end)

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      html = rendered(page)
      assert html =~ ~r{<section b-section>\s*<p>inside</p>\s*</section>}
      refute html =~ ~s(class="v1")
    end

    test "and restoring it queues the render that prints it again", c do
      page = page!(c.user, %{type: :container, container_id: c.container.id, children: [inside()]})
      {:ok, deleted} = Brando.Content.delete_container(c.container.id, c.user)
      {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
      refute rendered(page) =~ ~s(class="v1")

      job = queues_render(page, fn -> Brando.Authorization.Boundary.restore(c.user, deleted) end)

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      assert rendered(page) =~ ~s(<section class="v1"><p>inside</p></section>)
    end

    test "and restoring it tells the Release changes screen", c do
      {:ok, deleted} = Brando.Content.delete_container(c.container.id, c.user)
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Content.Definitions.topic())

      assert {:ok, _} = Brando.Authorization.Boundary.restore(c.user, deleted)
      assert_received {:definitions_changed, _prefix}
    end

    test "renders the blocks without a palette when theirs is in the trash", c do
      ink = palette!(c.user, "ink")
      block = %{type: :container, container_id: c.container.id, palette_id: ink.id, children: [inside()]}
      page = page!(c.user, block)
      {:ok, _} = Brando.Content.delete_palette(ink.id, c.user)

      job = queues_render(page, fn -> Brando.Content.delete_container(c.container.id, c.user) end)

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      html = rendered(page)
      assert html =~ ~r{<section b-section>\s*<p>inside</p>\s*</section>}
      refute html =~ ~s(class="v1")
    end
  end

  describe "a section whose palette is in the trash" do
    test "renders without a palette", c do
      ink = palette!(c.user, "ink")
      page = page!(c.user, %{type: :container, palette_id: ink.id, children: [inside()]})
      {:ok, _} = Brando.Content.delete_palette(ink.id, c.user)

      assert {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
      assert rendered(page) =~ ~r{<section b-section>\s*<p>inside</p>\s*</section>}
    end
  end

  describe "saving a palette" do
    test "queues the render of a page whose section uses it, which prints the new colour", c do
      page = page!(c.user, %{type: :container, palette_id: c.paper.id, children: [inside()]})
      assert rendered(page) =~ "--background: #fff9f4"

      job = queues_render(page, fn -> save_background(c.paper, c.user, "#000000") end)

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      html = rendered(page)
      assert html =~ "--background: #000000"
      refute html =~ "#fff9f4"
    end

    test "clears the cached containers holding it", c do
      page!(c.user, %{type: :container, container_id: c.container.id, children: [inside()]})
      assert [%{palette: %{colors: [%{hex_value: "#fff9f4"}]}}] = render_containers()

      assert {:ok, _} = save_background(c.paper, c.user, "#000000")

      assert [%{palette: %{colors: [%{hex_value: "#000000"}]}}] = render_containers()
    end
  end

  defp queues_render(page, change) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} = change.()
      assert [job] = all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: page.id})
      job
    end)
  end

  # Saved as the admin's form saves it (`BrandoAdmin.Components.Form`)
  defp save_background(palette, user, hex) do
    params = %{"colors" => [%{"name" => "Background", "key" => "background", "hex_value" => hex}]}
    palette |> Palette.changeset(params, user) |> Brando.Content.update_palette(user)
  end

  # The containers a render reads, as `Brando.Villain` lists them
  defp render_containers do
    {:ok, containers} = RenderSourceQuery.list_containers(%{preload: [:palette], cache: {:ttl, :infinite}})
    containers
  end

  defp palette!(user, key \\ "paper") do
    {:ok, palette} =
      Brando.Content.create_palette(
        %{
          "name" => String.capitalize(key),
          "namespace" => "site",
          "key" => key,
          "status" => "published",
          "colors" => [%{"name" => "Background", "key" => "background", "hex_value" => "#fff9f4"}]
        },
        user
      )

    palette
  end

  defp container!(user, palette) do
    {:ok, container} =
      Brando.Content.create_container(
        %{
          "name" => "Section",
          "namespace" => "Sections",
          "code" => ~s(<section class="v1">{{ content }}</section>),
          "type" => "liquid",
          "palette_id" => palette.id
        },
        user
      )

    container
  end

  defp inside do
    module = Factory.insert(:module, code: "<p>inside</p>", vars: [], refs: [])
    %{type: :module, module_id: module.id, source: source(), uid: uid()}
  end

  # A page whose one block is `block`; rendered
  defp page!(user, block) do
    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: Map.merge(%{source: source(), uid: uid()}, block)}])
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  defp rendered(page), do: Brando.Pages.get_page!(page.id).rendered_blocks

  defp source, do: "Elixir.Brando.Pages.Page.Blocks"
  defp uid, do: "block-#{System.unique_integer([:positive])}"
end
