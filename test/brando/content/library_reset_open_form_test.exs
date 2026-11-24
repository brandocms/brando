defmodule Brando.Content.LibraryResetOpenFormTest do
  # An editor has a page open whose block uses a site's override of a library
  # module, and an admin presses Reset to shared or Accept update. Those sync
  # the block with the module it uses now; the form's save, of the block as
  # it loaded it, syncs it too, so the save keeps the library's settings and
  # var and the editor's edit (#3901).
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Content.Module
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

    {:ok, library} = SharedLibrary.create_shared(:module, module_attrs(), user)
    :ok = SharedLibrary.enable(site, :module, library.id)
    {:ok, _override} = SharedLibrary.customize(:module, library.id, site, @prefix, user)

    %{user: user, site: site, library: library}
  end

  test "a save after Reset to shared keeps the library's var and settings and the editor's edit", c do
    # The site made the body a lede, edited in place: the override is still
    # v1, and the library is v2 after its update
    override = override(c.library)
    [body] = override.refs
    lede(body)
    page = page!(c.user, c.library)
    assert body_data(c.library).type == :lede

    form = loaded(page)
    library_update(c)
    :ok = SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user)
    assert var_keys(c.library) == ["headline"]

    form_save!(form, c.user, "<p>Edited during the reset</p>")

    assert var_keys(c.library) == ["headline"]
    assert body_data(c.library).type == :paragraph
    assert body_data(c.library).text == "<p>Edited during the reset</p>"
  end

  test "a save after Accept update keeps the library's var and settings and the editor's edit", c do
    # The site made the body a lede in the admin, with a code change, which
    # took the override to v2; the replacement an Accept makes is v1
    override = override(c.library)
    [body] = override.refs

    {:ok, _} =
      Tenant.with_prefix(@prefix, fn ->
        refs = [%{id: body.id, name: "body", data: %{type: "text", data: %{text: "Body", type: "lede"}}}]
        Brando.Content.update_module(override, %{code: "<p class=\"site\">{% ref refs.body %}</p>", refs: refs}, c.user)
      end)

    page = page!(c.user, c.library)
    assert body_data(c.library).type == :lede

    form = loaded(page)
    library_update(c)
    free_ref_uids(override)
    {:ok, _} = SharedLibrary.accept_update(:module, c.library.id, c.site, @prefix, c.user)
    assert var_keys(c.library) == ["headline"]

    form_save!(form, c.user, "<p>Edited during the update</p>")

    assert var_keys(c.library) == ["headline"]
    assert body_data(c.library).type == :paragraph
    assert body_data(c.library).text == "<p>Edited during the update</p>"
  end

  test "a save after Reset to shared, with the override and the library at the same version", c do
    # The site made the body a lede with a code change (override v2); the
    # library is v2 after its update
    override = override(c.library)
    customize_lede(override, c.user)
    page = page!(c.user, c.library)
    assert body_data(c.library).type == :lede

    form = loaded(page)
    library_update(c)
    :ok = SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user)
    assert block(c.library).module_version == form_block(form).module_version

    form_save!(form, c.user, "<p>Edited during the reset</p>")

    assert var_keys(c.library) == ["headline"]
    assert body_data(c.library).type == :paragraph
    assert body_data(c.library).text == "<p>Edited during the reset</p>"
  end

  test "a save after Accept update of an override never edited since it was customized", c do
    # The body made a lede in place: the override is still v1, as is the
    # replacement an Accept makes
    override = override(c.library)
    [body] = override.refs
    lede(body)
    page = page!(c.user, c.library)
    assert body_data(c.library).type == :lede

    form = loaded(page)
    library_update(c)
    free_ref_uids(override)
    {:ok, _} = SharedLibrary.accept_update(:module, c.library.id, c.site, @prefix, c.user)
    assert block(c.library).module_version == form_block(form).module_version

    form_save!(form, c.user, "<p>Edited during the update</p>")

    assert var_keys(c.library) == ["headline"]
    assert body_data(c.library).type == :paragraph
    assert body_data(c.library).text == "<p>Edited during the update</p>"
  end

  defp customize_lede(override, user) do
    [body] = override.refs

    {:ok, _} =
      Tenant.with_prefix(@prefix, fn ->
        refs = [%{id: body.id, name: "body", data: %{type: "text", data: %{text: "Body", type: "lede"}}}]
        Brando.Content.update_module(override, %{code: "<p class=\"site\">{% ref refs.body %}</p>", refs: refs}, user)
      end)
  end

  defp form_block(page), do: hd(page.entry_blocks).block

  defp module_attrs do
    %{
      name: %{"en" => "Teaser"},
      namespace: %{"en" => "general"},
      help_text: %{"en" => "Help"},
      class: "teaser",
      code: "<p>{% ref refs.body %}</p>",
      refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Body"}}}]
    }
  end

  # The library takes a var and puts its body back to a paragraph
  defp library_update(c) do
    library = Brando.Repo.preload(c.library, :refs, force: true)
    [body] = library.refs

    attrs = %{
      vars: [%{type: :text, label: "Headline", key: "headline", value: "Library headline", sequence: 0}],
      refs: [%{id: body.id, name: "body", data: %{type: "text", data: %{text: "Body", type: "paragraph"}}}],
      version_note: "Headline"
    }

    {:ok, _} = SharedLibrary.update_shared(:module, c.library.id, attrs, c.user)
  end

  defp override(library) do
    from(m in Module, where: m.source_module_id == ^library.id, preload: [:vars, :refs])
    |> Brando.Repo.one(prefix: @prefix)
  end

  defp lede(ref) do
    data = %{ref.data | data: %{ref.data.data | type: :lede}}
    ref |> Ecto.Changeset.change(data: data) |> Brando.Repo.update!(prefix: @prefix)
  end

  # The test's tenant schema is cloned without foreign keys, so deleting the
  # override leaves its refs, whose uids the replacement copies from the
  # library again
  defp free_ref_uids(override) do
    for ref <- override.refs,
        do: ref |> Ecto.Changeset.change(uid: Brando.Utils.generate_uid()) |> Brando.Repo.update!(prefix: @prefix)
  end

  # A page whose one block uses the library module, synced with the
  # override as a save of it does
  defp page!(user, library) do
    block = %{
      type: :module,
      module_id: library.id,
      module_origin: :shared,
      source: "Elixir.Brando.Pages.Page.Blocks",
      uid: "block-#{System.unique_integer([:positive])}"
    }

    Tenant.with_prefix(@prefix, fn ->
      changeset =
        %Page{}
        |> Page.changeset(Factory.params_for(:page), user)
        |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
        |> Map.put(:action, :insert)

      {:ok, page} = Brando.Pages.create_page(changeset, user)
      Blocks.render_entries_with_module_id(library.id, :shared)
      page
    end)
  end

  # The page as the form loads it
  defp loaded(page) do
    Tenant.with_prefix(@prefix, fn ->
      Page
      |> Brando.Repo.get!(page.id)
      |> Brando.Repo.preload(Brando.Content.BlockPreloads.for_schema(Page), force: true)
    end)
  end

  # The form's save: the block's body text edited, as the block field sends it
  defp form_save!(page, user, text) do
    entry_blocks =
      Enum.map(page.entry_blocks, fn %{block: block} = entry_block ->
        refs =
          Enum.map(block.refs, &%{"id" => to_string(&1.id), "data" => %{"type" => "text", "data" => %{"text" => text}}})

        Page.Blocks.changeset(entry_block, %{"block" => %{"id" => to_string(block.id), "refs" => refs}}, user.id, true)
      end)

    changeset = page |> Page.changeset(%{}, user) |> Ecto.Changeset.put_assoc(:entry_blocks, entry_blocks)
    {:ok, _} = Tenant.with_prefix(@prefix, fn -> Brando.Pages.update_page(changeset, user) end)
  end

  defp block(library) do
    query = from(b in Block, where: b.module_id == ^library.id and b.module_origin == :shared, preload: [:vars, :refs])
    Brando.Repo.one!(query, prefix: @prefix)
  end

  defp var_keys(library), do: Enum.map(block(library).vars, & &1.key)
  defp body_data(library), do: hd(block(library).refs).data.data
end
