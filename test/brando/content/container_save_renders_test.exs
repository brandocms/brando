defmodule Brando.Content.ContainerSaveRendersTest do
  # A container saved in the admin renders again the entries whose blocks
  # use it, as a module save does (#3847)
  use Brando.ConnCase, async: false

  alias Brando.Content.Container
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.SyncTest.Article

  setup do
    user = Factory.insert(:random_user)
    paper = palette!(user, "Paper", "paper")
    container = container!(user, paper)
    page = page_in_container!(user, container)
    %{user: user, container: container, page: page}
  end

  test "a template change queues the page's render, which prints the new template", c do
    assert rendered(c.page) =~ ~s(<section class="v1">)

    job = save_queues_render(c, %{"code" => ~s(<section class="v2">{{ content }}</section>)})

    assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
    html = rendered(c.page)
    assert html =~ ~s(<section class="v2"><p>inside</p></section>)
    refute html =~ ~s(class="v1")
  end

  # No markup reads the default palette yet (a Liquid container is given
  # `{{ content }}` only): the render runs and prints the same section
  test "a default palette change queues the render of a page whose block has no palette of its own", c do
    ink = palette!(c.user, "Ink", "ink")

    job = save_queues_render(c, %{"palette_id" => ink.id})

    assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
    assert rendered(c.page) =~ ~s(<section class="v1"><p>inside</p></section>)
  end

  # One article uses the container in its `blocks` field, the other in its
  # `notes` field: two join schemas, one entry schema
  test "a save queues the renders of entries using the container in different block fields of one Blueprint", c do
    in_blocks = article_in_container!(:entry_blocks, Article.Blocks, c.container)
    in_notes = article_in_container!(:entry_notes, Article.Notes, c.container)

    Oban.Testing.with_testing_mode(:manual, fn ->
      changeset = Container.changeset(c.container, %{"code" => ~s(<div>{{ content }}</div>)}, c.user)
      assert {:ok, _} = Brando.Content.update_container(changeset, c.user)

      for article <- [in_blocks, in_notes] do
        assert [_job] = all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: article.id})
      end
    end)
  end

  # Saved as the admin's form saves it (`BrandoAdmin.Components.Form`)
  defp save_queues_render(c, params) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      changeset = Container.changeset(c.container, params, c.user)
      assert {:ok, _} = Brando.Content.update_container(changeset, c.user)
      assert [job] = all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: c.page.id})
      job
    end)
  end

  defp palette!(user, name, key) do
    {:ok, palette} =
      Brando.Content.create_palette(
        %{
          "name" => name,
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

  # A page whose one block is in `container`, with no palette of its own, and
  # a module inside it; rendered
  defp page_in_container!(user, container) do
    module = Factory.insert(:module, code: "<p>inside</p>", vars: [], refs: [])
    source = "Elixir.Brando.Pages.Page.Blocks"

    blocks = [
      %{
        block: %{
          type: :container,
          uid: "section-#{System.unique_integer([:positive])}",
          source: source,
          container_id: container.id,
          children: [
            %{type: :module, module_id: module.id, source: source, uid: "inside-#{System.unique_integer([:positive])}"}
          ]
        }
      }
    ]

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, blocks)
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  defp article_in_container!(assoc, join_schema, container) do
    block = %Brando.Content.Block{
      type: :container,
      uid: "section-#{System.unique_integer([:positive])}",
      source: to_string(join_schema),
      container_id: container.id
    }

    Brando.Repo.insert!(struct(Article, [{:title, "Article"}, {assoc, [struct(join_schema, block: block)]}]))
  end

  defp rendered(page), do: Brando.Pages.get_page!(page.id).rendered_blocks
end
