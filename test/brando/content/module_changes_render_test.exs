defmodule Brando.Content.ModuleChangesRenderTest do
  # Putting a module in the trash or restoring it renders again the entries
  # whose blocks use it, and a restore tells the Release changes screen, as
  # a delete does (#3882). With Villain's production query caching on, so a
  # render reads the cached modules.
  use Brando.ConnCase, async: false

  alias Brando.Authorization.Boundary
  alias Brando.Factory
  alias Brando.Pages.Page

  setup do
    Application.put_env(:brando, :villain_query_cache, true)
    Cachex.clear(:query)

    on_exit(fn ->
      Application.delete_env(:brando, :villain_query_cache)
      Cachex.clear(:query)
    end)

    user = Factory.insert(:random_user)
    module = Factory.insert(:module, code: "<p>teaser</p>", vars: [], refs: [])
    %{user: user, module: module}
  end

  describe "putting a module in the trash" do
    test "queues the render of a page using it, which prints it no longer", c do
      page = page!(c.user, c.module)
      assert rendered(page) =~ "<p>teaser</p>"

      job = queues_render(page, fn -> Brando.Content.delete_module(c.module.id, c.user) end)

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      refute rendered(page) =~ "<p>teaser</p>"
    end

    test "and restoring it queues the render that prints it again", c do
      page = page!(c.user, c.module)
      {:ok, deleted} = Brando.Content.delete_module(c.module.id, c.user)
      {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
      refute rendered(page) =~ "<p>teaser</p>"

      job = queues_render(page, fn -> Boundary.restore(c.user, deleted) end)

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      assert rendered(page) =~ "<p>teaser</p>"
    end

    test "and restoring it tells the Release changes screen", c do
      {:ok, deleted} = Brando.Content.delete_module(c.module.id, c.user)
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Content.Definitions.topic())

      assert {:ok, _} = Boundary.restore(c.user, deleted)
      assert_received {:definitions_changed, _prefix}
    end
  end

  defp queues_render(page, change) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} = change.()
      assert [job] = all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: page.id})
      job
    end)
  end

  # A page whose one block uses `module`; rendered
  defp page!(user, module) do
    block = %{type: :module, module_id: module.id, source: source(), uid: "block-#{System.unique_integer([:positive])}"}

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  defp rendered(page), do: Brando.Pages.get_page!(page.id).rendered_blocks

  defp source, do: "Elixir.Brando.Pages.Page.Blocks"
end
