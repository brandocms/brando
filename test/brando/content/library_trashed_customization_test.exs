defmodule Brando.Content.LibraryTrashedCustomizationTest do
  # A site's customization of a library entry in the trash: Customize brings
  # it back with its edits, as the trash restores it, in a real tenant site.
  # Reset says when there is nothing to reset (#3902).
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Authorization.Groups
  alias Brando.Authorization.Scope
  alias Brando.Content
  alias Brando.Content.Container
  alias Brando.Content.Module
  alias Brando.Content.Palette
  alias Brando.Content.SharedLibrary
  alias Brando.Content.Var
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
    root = Path.join(System.tmp_dir!(), "brando-library-trash-#{System.unique_integer([:positive])}")
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

    %{user: user, site: site}
  end

  describe "a module customization in the trash" do
    setup c do
      attrs = Map.merge(module_attrs("<p>library {{ headline }}</p>"), %{vars: [headline_var("Library headline")]})
      {:ok, library} = SharedLibrary.create_shared(:module, attrs, c.user)
      :ok = SharedLibrary.enable(c.site, :module, library.id)
      {:ok, override} = SharedLibrary.customize(:module, library.id, c.site, @prefix, c.user)
      override |> Ecto.Changeset.change(code: "<p>site {{ headline }}</p>") |> Brando.Repo.update!(prefix: @prefix)

      page = Tenant.with_prefix(@prefix, fn -> page!(c.user, library) end)
      set_headline!(page, "Edited headline")
      rerender!(page)
      assert rendered(page) =~ "<p>site Edited headline</p>"

      # Its renders run inline: the page shows the library module
      {:ok, _} = Tenant.with_prefix(@prefix, fn -> Content.delete_module(override.id, c.user) end)
      assert rendered(page) =~ "<p>library Edited headline</p>"

      %{library: library, override: override, page: page}
    end

    test "comes back with its edits when the site customizes again, and its pages render it", c do
      assert {:ok, restored} = SharedLibrary.customize(:module, c.library.id, c.site, @prefix, c.user)

      assert restored.id == c.override.id

      assert [%Module{deleted_at: nil, code: "<p>site {{ headline }}</p>"}] =
               overrides(Module, :source_module_id, c.library)

      # The block keeps its value: a restore does not sync
      assert rendered(c.page) =~ "<p>site Edited headline</p>"
    end

    test "stays in the trash when the site accepts the library's update", c do
      {:ok, _} = SharedLibrary.update_shared(:module, c.library.id, %{class: "v2", version_note: "Two"}, c.user)

      assert {:error, :not_found} = SharedLibrary.accept_update(:module, c.library.id, c.site, @prefix, c.user)
      assert [%Module{deleted_at: %DateTime{}}] = overrides(Module, :source_module_id, c.library)
    end

    test "purged from the trash, leaves Customize to copy the library afresh", c do
      Brando.Repo.delete_all(from(m in Module, where: m.id == ^c.override.id), prefix: @prefix)

      assert {:ok, copy} = SharedLibrary.customize(:module, c.library.id, c.site, @prefix, c.user)
      assert copy.id != c.override.id

      assert [%Module{deleted_at: nil, code: "<p>library {{ headline }}</p>"}] =
               overrides(Module, :source_module_id, c.library)
    end
  end

  test "a container customization in the trash comes back with its edits", c do
    attrs = %{name: "Wrap", namespace: "general", help_text: "Help", code: "<main>{{ content }}</main>"}
    {:ok, library} = SharedLibrary.create_shared(:container, attrs, c.user)
    :ok = SharedLibrary.enable(c.site, :container, library.id)
    {:ok, override} = SharedLibrary.customize(:container, library.id, c.site, @prefix, c.user)
    override |> Ecto.Changeset.change(code: "<div>{{ content }}</div>") |> Brando.Repo.update!(prefix: @prefix)
    {:ok, _} = Tenant.with_prefix(@prefix, fn -> Content.delete_container(override.id, c.user) end)

    assert {:ok, restored} = SharedLibrary.customize(:container, library.id, c.site, @prefix, c.user)
    assert restored.id == override.id

    assert [%Container{deleted_at: nil, code: "<div>{{ content }}</div>"}] =
             overrides(Container, :source_container_id, library)
  end

  describe "a palette customization in the trash" do
    setup c do
      {:ok, library} = SharedLibrary.create_shared(:palette, palette_attrs("#0000ff"), c.user)
      :ok = SharedLibrary.enable(c.site, :palette, library.id)
      {:ok, override} = SharedLibrary.customize(:palette, library.id, c.site, @prefix, c.user)
      {:ok, _} = override |> Palette.changeset(%{colors: [ink("#ff0000")]}, c.user) |> Brando.Repo.update(prefix: @prefix)
      {:ok, _} = Tenant.with_prefix(@prefix, fn -> Content.delete_palette(override.id, c.user) end)
      css = palettes_css()
      assert css =~ "#0000ff"
      refute css =~ "#ff0000"

      %{library: library, override: override}
    end

    test "comes back with its colours, in the site's palette CSS", c do
      assert {:ok, restored} = SharedLibrary.customize(:palette, c.library.id, c.site, @prefix, c.user)
      assert restored.id == c.override.id
      assert [%Palette{deleted_at: nil}] = overrides(Palette, :source_palette_id, c.library)

      css = palettes_css()
      assert css =~ "#ff0000"
      refute css =~ "#0000ff"
    end

    # A site's palettes are not code: groups grant them, update and restore apart
    test "stays in the trash for an editor who may change palettes but not restore them", c do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      {:ok, _} = Brando.Authorization.Migration.run()
      environment = Brando.Tenant.Registry.get_environment_by_key(c.site, "production")

      member = fn keys ->
        member = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
        scope = Scope.site(c.user, c.site, environment)
        {:ok, group} = Groups.create(scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
        {:ok, :ok} = Groups.add_member(scope, group.id, member.id)
        member
      end

      # A published palette's restore takes publish too, as from the trash
      keys = ~w(brando.admin.access brando.content_palettes.read brando.content_palettes.update
                brando.content_palettes.publish)

      editor = member.(keys)

      assert {:error, :forbidden} = SharedLibrary.customize(:palette, c.library.id, c.site, @prefix, editor)
      assert [%Palette{deleted_at: %DateTime{}}] = overrides(Palette, :source_palette_id, c.library)

      restorer = member.(["brando.content_palettes.restore" | keys])

      assert {:ok, restored} = SharedLibrary.customize(:palette, c.library.id, c.site, @prefix, restorer)
      assert restored.id == c.override.id
    end
  end

  test "a reset with no customization to discard says so", c do
    {:ok, library} = SharedLibrary.create_shared(:module, module_attrs("<p>library</p>"), c.user)
    :ok = SharedLibrary.enable(c.site, :module, library.id)

    assert {:error, :not_customized} = SharedLibrary.reset(:module, library.id, c.site, @prefix, c.user)
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

  defp palette_attrs(hex),
    do: %{name: "Ink", key: "ink", namespace: "general", status: :published, colors: [ink(hex)]}

  defp ink(hex), do: %{name: "Ink", key: "ink", hex_value: hex}

  defp headline_var(value), do: %{type: :text, label: "Headline", key: "headline", value: value, sequence: 0}

  # A page whose one block uses the library module, with its var; rendered
  defp page!(user, library) do
    block = %{
      type: :module,
      module_id: library.id,
      module_origin: :shared,
      source: "Elixir.Brando.Pages.Page.Blocks",
      uid: "block-#{System.unique_integer([:positive])}",
      vars: [headline_var("Library headline")]
    }

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    page
  end

  defp set_headline!(page, value) do
    {1, _} =
      Brando.Repo.update_all(
        from(v in Var,
          join: eb in "pages_blocks",
          on: eb.block_id == v.block_id,
          where: eb.entry_id == ^page.id and v.key == "headline"
        ),
        [set: [value: value]],
        prefix: @prefix
      )
  end

  defp rerender!(page), do: {:ok, _} = Tenant.with_prefix(@prefix, fn -> Content.Blocks.render_entry(Page, page.id) end)

  defp overrides(schema, source_field, library) do
    Brando.Repo.all(from(e in schema, where: field(e, ^source_field) == ^library.id), prefix: @prefix)
  end

  defp palettes_css,
    do: Tenant.with_prefix(@prefix, fn -> Phoenix.HTML.safe_to_string(Brando.Cache.Palettes.get_css()) end)

  defp rendered(page), do: Brando.Repo.get!(Page, page.id, prefix: @prefix).rendered_blocks
end
