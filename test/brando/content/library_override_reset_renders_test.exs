defmodule Brando.Content.LibraryOverrideResetRendersTest do
  # Reset and Accept update on the shared library screen replace or remove a
  # site's override of a library module: the environment's entries whose
  # blocks use it render again, with the library's code (#3882).
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Definitions
  alias Brando.Content.Module
  alias Brando.Content.Palette
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

  # The library takes a var the page's block lacks; the sync under the
  # override (which lacks it too) leaves the block without it
  test "resetting the override syncs the block with the library module and queues its render", c do
    attrs = %{code: "<p>library {{ headline }}</p>", vars: [headline_var()], version_note: "Headline"}
    {:ok, _} = SharedLibrary.update_shared(:module, c.library.id, attrs, c.user)
    assert block_var_keys(c.library) == []

    job = queues_render(c.page, fn -> SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user) end)

    assert block_var_keys(c.library) == ["headline"]
    assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
    html = rendered(c.page)
    assert html =~ "<p>library Library headline</p>"
    refute html =~ "<p>site</p>"
  end

  test "accepting the library's update syncs the block with it and queues the render that prints it", c do
    attrs = %{code: "<p>library v2 {{ headline }}</p>", vars: [headline_var()], version_note: "New copy"}
    {:ok, _} = SharedLibrary.update_shared(:module, c.library.id, attrs, c.user)
    assert rendered(c.page) =~ "<p>site</p>"
    assert block_var_keys(c.library) == []

    job =
      queues_render(c.page, fn -> SharedLibrary.accept_update(:module, c.library.id, c.site, @prefix, c.user) end)

    assert block_var_keys(c.library) == ["headline"]
    assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
    html = rendered(c.page)
    assert html =~ "<p>library v2 Library headline</p>"
    refute html =~ "<p>site</p>"
  end

  # A Reset that fails after the override is gone keeps it, and has queued
  # nothing: the pages still show the override, and Reset can be tried again
  test "a reset whose block sync fails keeps the override and queues no render", c do
    # The sync then finds no module for the blocks, and raises
    Brando.Repo.delete_all(from(m in Module, where: m.id == ^c.library.id), prefix: "public")

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert_raise BadMapError, fn ->
        SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user)
      end

      assert [] = all_enqueued(worker: Brando.Worker.EntryRenderer)
    end)

    assert override(c.library)
  end

  test "two resets at once both succeed, and the page's render is queued", c do
    # Oban runs a job inline when any process in the caller chain is inline
    manual_reset = fn ->
      Oban.Testing.with_testing_mode(:manual, fn ->
        SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user)
      end)
    end

    Oban.Testing.with_testing_mode(:manual, fn ->
      results = [Task.async(manual_reset), Task.async(manual_reset)] |> Task.await_many()

      assert results == [:ok, :ok]
      assert [_job] = all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: c.page.id})
    end)

    refute override(c.library)
  end

  test "customizing, resetting and accepting an update tell the Release changes screen", c do
    Phoenix.PubSub.subscribe(Brando.pubsub(), Definitions.topic())

    :ok = SharedLibrary.reset(:module, c.library.id, c.site, @prefix, c.user)
    assert_receive {:definitions_changed, @prefix}

    {:ok, _} = SharedLibrary.customize(:module, c.library.id, c.site, @prefix, c.user)
    assert_receive {:definitions_changed, @prefix}

    {:ok, _} = SharedLibrary.accept_update(:module, c.library.id, c.site, @prefix, c.user)
    assert_receive {:definitions_changed, @prefix}
  end

  describe "a palette override" do
    setup c do
      {:ok, library} =
        SharedLibrary.create_shared(
          :palette,
          %{name: "Ink", key: "ink", namespace: "general", status: :published, colors: [ink("#0000ff")]},
          c.user
        )

      :ok = SharedLibrary.enable(c.site, :palette, library.id)
      {:ok, override} = SharedLibrary.customize(:palette, library.id, c.site, @prefix, c.user)

      {:ok, _} =
        override
        |> Palette.changeset(%{colors: [ink("#ff0000")]}, c.user)
        |> Brando.Repo.update(prefix: @prefix)

      # Warm: what a visitor's page read while the override was red
      assert palettes_css() =~ "#ff0000"
      %{palette: library}
    end

    test "reset leaves the site's palette CSS", c do
      :ok = SharedLibrary.reset(:palette, c.palette.id, c.site, @prefix, c.user)
      refute palettes_css() =~ "#ff0000"
    end

    test "accepting the library's version puts its colours in the site's palette CSS", c do
      {:ok, _} = SharedLibrary.accept_update(:palette, c.palette.id, c.site, @prefix, c.user)
      css = palettes_css()
      assert css =~ "#0000ff"
      refute css =~ "#ff0000"
    end
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

  defp headline_var, do: %{type: :text, label: "Headline", key: "headline", value: "Library headline", sequence: 0}

  defp ink(hex), do: %{name: "Ink", key: "ink", hex_value: hex}

  # The vars of the page's block
  defp block_var_keys(library) do
    query = from(b in Block, where: b.module_id == ^library.id and b.module_origin == :shared, preload: :vars)
    [block] = Brando.Repo.all(query, prefix: @prefix)
    Enum.map(block.vars, & &1.key)
  end

  defp override(library),
    do: Brando.Repo.one(from(m in Module, where: m.source_module_id == ^library.id), prefix: @prefix)

  defp palettes_css,
    do: Tenant.with_prefix(@prefix, fn -> Phoenix.HTML.safe_to_string(Brando.Cache.Palettes.get_css()) end)

  defp rendered(page), do: Brando.Repo.get!(Page, page.id, prefix: @prefix).rendered_blocks
end
