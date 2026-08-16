defmodule Brando.Assets.SiteAssetsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.Vite.Manifest
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  setup do
    root = Path.join(System.tmp_dir!(), "brando-site-assets-#{System.unique_integer([:positive])}")
    media_path = Path.join(root, "media")
    sites_path = Path.join(root, "sites")
    site_assets_path = Path.join(root, "site_assets")

    put_test_env(:tenancy_mode, :none)
    put_test_env(:media_path, media_path)
    put_test_env(:sites_path, sites_path)
    put_test_env(:site_assets_path, site_assets_path)
    SiteAssets.invalidate_cache()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      SiteAssets.invalidate_cache()
      Brando.Tenant.Cache.clear()
      :persistent_term.erase({:vite, "cache_manifest"})
      :persistent_term.erase({:vite, "critical_css"})
    end)

    %{root: root}
  end

  test "registers, activates, serves, and reverts a standalone set" do
    set_path = create_set(nil, "20260816_abc123", "standalone", "standalone.css")

    assert {:ok, registered} =
             SiteAssets.register_set(set_path, %{
               uploaded_at: "2026-08-16T12:30:00Z",
               revision: "abc123"
             })

    refute registered.active
    assert registered.file_count == 3
    assert registered.size > 0
    assert registered.metadata["revision"] == "abc123"
    assert SiteAssets.cached() == nil
    refute Brando.Plug.SiteAssets.call(conn("assets/20260816_abc123.js"), []).halted

    assert {:ok, active} = SiteAssets.activate_set(registered.id)
    assert active.active

    assert %{files: files, manifest: manifest} = SiteAssets.cached()
    assert MapSet.member?(files, "assets/20260816_abc123.js")
    assert manifest["src/main.js"]["file"] == "assets/20260816_abc123.js"

    served = Brando.Plug.SiteAssets.call(conn("assets/20260816_abc123.js"), [])
    assert served.halted
    assert served.status == 200
    assert served.resp_body == "standalone"

    parsed_manifest = Manifest.read(:app)
    assert parsed_manifest.entries.files == ["/assets/20260816_abc123.js"]
    assert parsed_manifest.entries.css_files == ["/assets/standalone.css"]

    assert :ok = SiteAssets.deactivate()
    assert SiteAssets.cached() == nil
    refute Brando.Plug.SiteAssets.call(conn("assets/20260816_abc123.js"), []).halted
  end

  test "activation validates manifests before replacing the current set" do
    first_path = create_set(nil, "first", "first", "first.css")
    assert {:ok, first} = SiteAssets.register_set(first_path)
    assert {:ok, _active} = SiteAssets.activate_set(first.id)

    invalid_path = Path.join(SiteAssets.sets_root(nil), "invalid")
    File.mkdir_p!(invalid_path)
    File.write!(Path.join(invalid_path, "manifest.json"), "not-json")

    assert {:ok, invalid} = SiteAssets.register_set(invalid_path)
    assert {:error, {:invalid_asset_manifest, _, _}} = SiteAssets.activate_set(invalid.id)
    assert SiteAssets.active_set().id == first.id
  end

  test "rejects registration outside the managed sets directory", %{root: root} do
    outside = Path.join(root, "outside")
    File.mkdir_p!(outside)

    assert {:error, {:invalid_asset_set_path, _, _}} = SiteAssets.register_set(outside)
  end

  test "isolates active files and manifests per site host" do
    put_test_env(:tenancy_mode, :multi)
    Brando.Tenant.Cache.clear()

    {:ok, acme} = create_site("Asset Acme", "asset-acme", "assets.acme.test")
    {:ok, beta} = create_site("Asset Beta", "asset-beta", "assets.beta.test")

    acme_path = create_set(acme, "acme-set", "acme-js", "acme.css")
    beta_path = create_set(beta, "beta-set", "beta-js", "beta.css")

    assert {:ok, acme_set} = SiteAssets.register_set(acme, acme_path, %{revision: "acme"})
    assert {:ok, beta_set} = SiteAssets.register_set(beta.key, beta_path, %{revision: "beta"})
    assert {:ok, _active} = SiteAssets.activate_set(acme_set.id)
    assert {:ok, _active} = SiteAssets.activate_set(beta_set.id)

    acme_conn = Brando.Plug.SiteAssets.call(conn("assets/acme-set.js", "assets.acme.test"), [])
    beta_conn = Brando.Plug.SiteAssets.call(conn("assets/beta-set.js", "assets.beta.test"), [])

    assert acme_conn.resp_body == "acme-js"
    assert beta_conn.resp_body == "beta-js"
    refute Brando.Plug.SiteAssets.call(conn("assets/acme-set.js", "assets.beta.test"), []).halted

    Tenant.put_prefix(Tenant.prefix(acme.key, "production"))
    assert Manifest.read(:app).entries.files == ["/assets/acme-set.js"]

    Tenant.put_prefix(Tenant.prefix(beta.key, "production"))
    assert Manifest.read(:app).entries.files == ["/assets/beta-set.js"]
  end

  defp create_set(site, name, js_content, css_file) do
    path = Path.join(SiteAssets.sets_root(site), name)
    File.mkdir_p!(Path.join(path, "assets"))
    File.write!(Path.join([path, "assets", "#{name}.js"]), js_content)
    File.write!(Path.join([path, "assets", css_file]), "body{}")

    manifest = %{
      "src/main.js" => %{
        "isEntry" => true,
        "file" => "assets/#{name}.js",
        "css" => ["assets/#{css_file}"]
      }
    }

    File.write!(Path.join(path, "manifest.json"), Jason.encode!(manifest))
    path
  end

  defp create_site(name, key, domain) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true,
        domain: domain
      })

    {:ok, Registry.get_site(site.id)}
  end

  defp conn(relative_path, host \\ "standalone.test") do
    :get
    |> Plug.Test.conn("https://#{host}/#{relative_path}")
    |> Map.put(:host, host)
  end
end
