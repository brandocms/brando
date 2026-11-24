defmodule Brando.Cache.SharedPalettesCssTest do
  # The site's palette CSS holds the palettes its content resolves: its own,
  # and the shared ones enabled for it or used by its blocks, a customized one
  # in place of its shared one. Each shared library action rebuilds it in the
  # site's environments, once it commits (#3902).
  use Brando.ConnCase, async: false

  alias Brando.Content.Palette
  alias Brando.Content.SharedLibrary
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias BrandoAdmin.Components.Form.Input

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  @production "tenant_acme_production"
  @staging "tenant_acme_staging"
  @other "tenant_beta_production"

  setup do
    user = Factory.insert(:random_user, role: :superuser)
    root = Path.join(System.tmp_dir!(), "brando-palettes-css-#{System.unique_integer([:positive])}")
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
      Brando.TenantCaches.clear([@production, @staging, @other])
    end)

    {:ok, site} =
      Tenant.Setup.create_site(
        %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
        user,
        environments: [
          %{name: "Production", key: "production", live: true, domain: "acme.test"},
          %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"}
        ]
      )

    {:ok, _other} =
      Tenant.Setup.create_site(
        %{name: "Beta", key: "beta", languages: ["en"], default_language: "en", status: :active},
        user,
        environments: [%{name: "Production", key: "production", live: true, domain: "beta.test"}]
      )

    {:ok, library} = SharedLibrary.create_shared(:palette, palette_attrs("ink", "#0000ff"), user)

    # Warm: what visitors' pages read before
    for prefix <- [@production, @staging, @other], do: refute(css(prefix) =~ "#0000ff")

    %{user: user, site: site, library: library}
  end

  test "a shared palette enabled for the site is in its palette CSS, in each of its environments", c do
    :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)

    assert css(@production) =~ "#0000ff"
    assert css(@staging) =~ "#0000ff"
    refute css(@other) =~ "#0000ff"

    :ok = SharedLibrary.disable(c.site, :palette, c.library.id, c.user)
    refute css(@production) =~ "#0000ff"
  end

  test "enabling rebuilds the CSS once it commits, and not when it rolls back", c do
    {:error, :rolled_back} =
      Brando.Repo.transaction(fn ->
        :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
        Brando.Repo.rollback(:rolled_back)
      end)

    refute css(@production) =~ "#0000ff"

    {:ok, :ok} =
      Brando.Repo.transaction(fn ->
        :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
        # Read inside, the allowlist is still the old one
        refute css(@production) =~ "#0000ff"
        :ok
      end)

    assert css(@production) =~ "#0000ff"
  end

  # Another node hears "forget the allowlist" and "rebuild the palettes" as
  # two refreshes, and runs them in whichever order
  test "another node's rebuild holds a palette enabled there before it forgets the allowlist", c do
    :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
    # This node's allowlist as it was before the other node enabled it
    SharedLibrary.Cache.put(c.site.id, :palette, [])

    :ok = Brando.Cache.refresh_node_cache({:palettes, @production})
    :ok = SharedLibrary.Cache.refresh_node_cache({c.site.id, :palette})

    assert css(@production) =~ "#0000ff"
  end

  test "customizing one palette and enabling another in one transaction holds both in the CSS", c do
    {:ok, other} = SharedLibrary.create_shared(:palette, palette_attrs("other", "#00aa00"), c.user)
    :ok = SharedLibrary.enable(c.site, :palette, other.id, c.user)

    {:ok, :ok} =
      Brando.Repo.transaction(fn ->
        {:ok, _override} = SharedLibrary.customize(:palette, other.id, c.site, @production, c.user)
        :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
      end)

    production = css(@production)
    assert production =~ "#00aa00"
    assert production =~ "#0000ff"
  end

  test "a customized palette is in the CSS in place of its shared one", c do
    :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
    {:ok, override} = SharedLibrary.customize(:palette, c.library.id, c.site, @production, c.user)

    {:ok, _} =
      override |> Palette.changeset(%{colors: [ink("#ff0000")]}, c.user) |> Brando.Repo.update(prefix: @production)

    Tenant.with_prefix(@production, fn -> Brando.Cache.rebuild_after_commit(:palettes) end)

    production = css(@production)
    assert production =~ "#ff0000"
    refute production =~ "#0000ff"
    # The customization is the production environment's
    assert css(@staging) =~ "#0000ff"
  end

  describe "a shared palette disabled while blocks use it" do
    setup c do
      :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
      Tenant.with_prefix(@production, fn -> page!(c.user, c.library) end)
      :ok
    end

    test "stays in the CSS, as the blocks still resolve it", c do
      :ok = SharedLibrary.disable(c.site, :palette, c.library.id, c.user)

      assert css(@production) =~ "#0000ff"
      # No block of the staging environment uses it
      refute css(@staging) =~ "#0000ff"
    end

    test "stays in the CSS as the site's customization, not both", c do
      {:ok, override} = SharedLibrary.customize(:palette, c.library.id, c.site, @production, c.user)

      {:ok, _} =
        override |> Palette.changeset(%{colors: [ink("#ff0000")]}, c.user) |> Brando.Repo.update(prefix: @production)

      :ok = SharedLibrary.disable(c.site, :palette, c.library.id, c.user)

      production = css(@production)
      assert production =~ "#ff0000"
      refute production =~ "#0000ff"
    end
  end

  test "the site's own palette wins a namespace and key it shares with a library palette", c do
    {:ok, _local} =
      Tenant.with_prefix(@production, fn ->
        %Palette{} |> Palette.changeset(palette_attrs("ink", "#00ff00"), c.user) |> Brando.Repo.insert()
      end)

    :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)

    production = css(@production)
    assert production =~ "#00ff00"
    refute production =~ "#0000ff"
  end

  test "a change to the shared palette rebuilds the CSS of the sites that use it", c do
    :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
    assert css(@production) =~ "#0000ff"

    {:ok, _} =
      SharedLibrary.update_shared(:palette, c.library.id, %{colors: [ink("#00ffff")], version_note: "Cyan"}, c.user)

    assert css(@production) =~ "#00ffff"
    assert css(@staging) =~ "#00ffff"
    refute css(@other) =~ "#00ffff"
  end

  # The colour input looks a palette up by its local id; the CSS by what the
  # blocks resolve
  test "the colour input reads the environment's own palettes, the CSS the shared ones as well", c do
    # The site's own palette under the library palette's integer id
    {:ok, local} =
      Tenant.with_prefix(@production, fn ->
        %Palette{id: c.library.id}
        |> Palette.changeset(palette_attrs("local", "#00ff00"), c.user)
        |> Brando.Repo.insert()
      end)

    :ok = SharedLibrary.enable(c.site, :palette, c.library.id, c.user)
    {:ok, override} = SharedLibrary.customize(:palette, c.library.id, c.site, @production, c.user)

    {:ok, _} =
      override |> Palette.changeset(%{colors: [ink("#ff0000")]}, c.user) |> Brando.Repo.update(prefix: @production)

    refute override.id == local.id
    # As a palette save does
    Tenant.with_prefix(@production, fn -> Brando.Cache.rebuild_after_commit(:palettes) end)

    Tenant.with_prefix(@production, fn ->
      assert Input.palette_colors(local.id) == "#00ff00"
      assert Input.palette_colors(override.id) == "#ff0000"
    end)

    production = css(@production)
    assert production =~ "#00ff00"
    assert production =~ "#ff0000"
    refute production =~ "#0000ff"
  end

  defp palette_attrs(key, hex),
    do: %{name: "Ink", key: key, namespace: "general", status: :published, colors: [ink(hex)]}

  defp ink(hex), do: %{name: "Ink", key: "ink", hex_value: hex}

  # A page with a block that uses the library palette
  defp page!(user, library) do
    block = %{
      type: :container,
      palette_id: library.id,
      palette_origin: :shared,
      source: "Elixir.Brando.Pages.Page.Blocks",
      uid: "block-#{System.unique_integer([:positive])}"
    }

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    page
  end

  defp css(prefix), do: Tenant.with_prefix(prefix, fn -> Phoenix.HTML.safe_to_string(Brando.Cache.Palettes.get_css()) end)
end
