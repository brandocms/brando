defmodule Brando.Content.LibraryOverrideResetRendersTest do
  # Reset and Accept update on the shared library screen replace or remove a
  # site's override of a library module: the environment's entries whose
  # blocks use it render again, with the library's code (#3882).
  use Brando.ConnCase, async: false

  alias Brando.Content.SharedLibrary
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Tenant

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  @prefix "tenant_acme_production"

  setup do
    user = Factory.insert(:random_user, role: :superuser)
    root = Path.join(System.tmp_dir!(), "brando-library-#{System.unique_integer([:positive])}")
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:tenancy_mode, :multi, global: true)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()
    SharedLibrary.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      SharedLibrary.Cache.clear()
      Brando.TenantCaches.clear([@prefix])
    end)

    {:ok, site} =
      Tenant.Setup.create_site(
        %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
        user,
        environments: [%{name: "Production", key: "production", live: true, domain: "acme.test"}]
      )

    {:ok, library} = SharedLibrary.create_shared(:module, module_attrs("<p>library</p>"), user)
    :ok = SharedLibrary.enable(site, :module, library.id)
    {:ok, override} = SharedLibrary.customize(:module, library.id, site, @prefix, user)
    override |> Ecto.Changeset.change(code: "<p>site</p>") |> Brando.Repo.update!(prefix: @prefix)

    page = Tenant.with_prefix(@prefix, fn -> page!(user, library) end)
    assert rendered(page) =~ "<p>site</p>"

    %{user: user, site: site, library: library, page: page}
  end

  test "resetting the override queues the render that prints the library module", c do
    job = queues_render(c.page, fn -> SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user) end)

    assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
    html = rendered(c.page)
    assert html =~ "<p>library</p>"
    refute html =~ "<p>site</p>"
  end

  test "accepting the library's update queues the render that prints it", c do
    attrs = %{code: "<p>library v2</p>", version_note: "New copy"}
    {:ok, _} = SharedLibrary.update_shared(:module, c.library.id, attrs, c.user)
    assert rendered(c.page) =~ "<p>site</p>"

    job =
      queues_render(c.page, fn -> SharedLibrary.accept_update(:module, c.library.id, c.site, @prefix, c.user) end)

    assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
    html = rendered(c.page)
    assert html =~ "<p>library v2</p>"
    refute html =~ "<p>site</p>"
  end

  defp queues_render(page, change) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert result = change.()
      assert result == :ok or match?({:ok, _}, result)
      assert [job] = all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: page.id})
      job
    end)
  end

  defp module_attrs(code) do
    %{
      name: %{"en" => "Teaser"},
      namespace: %{"en" => "general"},
      help_text: %{"en" => "Help"},
      class: "teaser",
      code: code
    }
  end

  # A page whose one block uses the library module; rendered
  defp page!(user, library) do
    block = %{
      type: :module,
      module_id: library.id,
      module_origin: :shared,
      source: "Elixir.Brando.Pages.Page.Blocks",
      uid: "block-#{System.unique_integer([:positive])}"
    }

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  defp rendered(page), do: Brando.Repo.get!(Page, page.id, prefix: @prefix).rendered_blocks
end
