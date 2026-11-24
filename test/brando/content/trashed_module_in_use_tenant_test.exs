defmodule Brando.Content.TrashedModuleInUseTenantTest do
  # A save's check for modules in the trash, in a site's environment (#3902):
  # a block finds its module as it renders, by origin. A site module and a
  # library module share an integer id here.
  use Brando.ConnCase, async: false

  alias Brando.Content.Module
  alias Brando.Content.SharedLibrary
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Tenant

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  @prefix "tenant_trash3902_production"

  setup do
    user = Factory.insert(:random_user, role: :superuser)
    root = Path.join(System.tmp_dir!(), "brando-trashed-module-#{System.unique_integer([:positive])}")
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
        %{name: "Trash", key: "trash3902", languages: ["en"], default_language: "en", status: :active},
        user,
        seed: false,
        environments: [%{name: "Production", key: "production", live: true, domain: "trash3902.test"}]
      )

    {:ok, library} = SharedLibrary.create_shared(:module, module_attrs("Library teaser"), user)
    :ok = SharedLibrary.enable(site, :module, library.id)

    # The site's own module with the library module's id, in the trash
    local =
      %Module{id: library.id}
      |> Ecto.Changeset.change(Map.put(module_attrs("Site teaser"), :uid, "sitetsr"))
      |> Repo.insert!(prefix: @prefix)
      |> Repo.soft_delete!()

    %{user: user, site: site, library: library, local: local}
  end

  test "a block of the site's module in the trash is refused, though the library has a live one of its id", c do
    assert {:error, {:module_in_trash, %{module: %{"en" => "Site teaser"}}}} =
             in_site(fn -> create_page(c.user, block(c.local.id, :local)) end)
  end

  test "a block of the library module saves, though the site's module of its id is in the trash", c do
    assert {:ok, %Page{}} = in_site(fn -> create_page(c.user, block(c.library.id, :shared)) end)
  end

  # Its blocks render as the library module
  test "a block of a library module whose customization is in the trash saves", c do
    {:ok, override} = SharedLibrary.customize(:module, c.library.id, c.site, @prefix, c.user)
    {:ok, _} = in_site(fn -> Brando.Content.delete_module(override.id, c.user) end)

    assert {:ok, %Page{}} = in_site(fn -> create_page(c.user, block(c.library.id, :shared)) end)
  end

  defp in_site(fun), do: Tenant.with_prefix(@prefix, fun)

  defp block(id, origin),
    do: %{
      type: :module,
      module_id: id,
      module_origin: origin,
      source: "Elixir.Brando.Pages.Page.Blocks",
      uid: "block-#{System.unique_integer([:positive])}"
    }

  defp create_page(user, block) do
    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
      |> Map.put(:action, :insert)

    Pages.create_page(changeset, user)
  end

  defp module_attrs(name) do
    %{
      name: %{"en" => name},
      namespace: %{"en" => "general"},
      help_text: %{"en" => "Help"},
      class: "teaser",
      code: "<p>#{name}</p>"
    }
  end
end
