defmodule Brando.Assets.PreviewAssetsTest do
  # In `:multi` the admin serves live previews and shared previews from its
  # own host, which belongs to no site. Their pages name the site's assets
  # host-relative, so that host must answer them from the site's sets.
  use Brando.ConnCase, async: false

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssetSet
  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Brando.SiteAssetsFixtures
  alias Brando.Sites.Preview
  alias Brando.Tenant
  alias Brando.Tenant.Frontend
  alias Brando.Tenant.Registry

  @admin_host "admin.test"

  defmodule Layouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns) do
      ~H|<html>
  <head><Brando.HTML.include_assets /></head><body>{@inner_content}</body>
</html>|
    end
  end

  defmodule PageHTML do
    @moduledoc false
    use Phoenix.Component

    def default(assigns), do: ~H|<main>{@page.title}</main>|
  end

  defmodule AcmeFrontend do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: PageHTML
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-preview-assets-#{System.unique_integer([:positive])}")
    release = Path.join(root, "release")
    File.mkdir_p!(Path.join(release, "assets"))

    # Pages name their built assets, as in production
    put_test_env(:env, :prod)
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:site_assets_path, Path.join(root, "site_assets"))
    put_test_env(:release_static_path, release)
    put_test_env(:site_frontends, %{"acme" => AcmeFrontend})
    reset_caches()
    Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      reset_caches()
      Tenant.Cache.clear()
    end)

    # Not cut over yet: no environment holds a domain
    {:ok, acme} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(acme, %{name: "Production", key: "production", live: true}, actor: :system)

    {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "beta", "beta.test")
    acme = Registry.get_site(acme.id)
    acme_set = activate(acme, "acme-one")

    %{acme: acme, beta: beta, acme_set: acme_set, release: release}
  end

  test "a live preview loads its site's active set on the admin's host", %{acme_set: acme_set} do
    Tenant.put_prefix(Tenant.prefix("acme", "production"))
    html = LivePreview.render(Page, page(), nil, target: :site)

    assert asset_paths(html) == ["assets/acme-one.css", "assets/acme-one.js"]
    assert Frontend.resolve(@admin_host) == nil
    assert_served(html, @admin_host, acme_set)
  end

  test "a shared preview loads its pinned set on its link's host, after another set is activated", %{
    acme: acme,
    acme_set: acme_set
  } do
    user = Brando.Factory.insert(:random_user, avatar: nil)
    Tenant.put_prefix(Tenant.prefix("acme", "production"))
    changeset = page() |> Map.put(:key, "about") |> Ecto.Changeset.change()

    assert {:ok, url, _days} = LivePreview.share(Page, changeset, user, %{}, :site)

    # The link is on the endpoint's host, which belongs to no site
    %URI{host: host, path: "/__p__/" <> key} = URI.parse(url)
    assert Frontend.resolve(host) == nil

    activate(acme, "acme-two")
    Tenant.put_prefix(nil)

    html = BrandoWeb.PreviewController.show(build_conn(), %{"preview_key" => key}).resp_body
    assert asset_paths(html) == ["assets/acme-one.css", "assets/acme-one.js"]
    assert_served(html, host, acme_set)
  end

  test "a path outside every manifest stays unanswered on the admin's host" do
    for path <- ["favicon.ico", "manifest.json", "assets/missing.js", "assets/acme-one.js/x"] do
      refute served?(path, @admin_host), path
    end
  end

  test "the release's file wins over a set's", %{release: release} do
    File.write!(Path.join(release, "assets/acme-one.js"), "release")

    refute served?("assets/acme-one.js", @admin_host)
    assert served?("assets/acme-one.css", @admin_host)
  end

  test "a host that resolves to a site gets that site's sets only", %{beta: beta} do
    beta_set = activate(beta, "beta-one")

    assert body("assets/beta-one.js", "beta.test") == File.read!(Path.join(beta_set.path, "assets/beta-one.js"))
    refute served?("assets/acme-one.js", "beta.test")

    # Every site's set answers on the admin's host
    assert served?("assets/acme-one.js", @admin_host)
    assert served?("assets/beta-one.js", @admin_host)
  end

  test "follows activation, deactivation, pinning and a preview's expiry", %{acme: acme} do
    assert served?("assets/acme-one.js", @admin_host)

    two = activate(acme, "acme-two")
    assert served?("assets/acme-two.js", @admin_host)
    refute served?("assets/acme-one.js", @admin_host)

    assert :ok = SiteAssets.deactivate(acme)
    refute served?("assets/acme-two.js", @admin_host)

    # Pinned as sharing pins it
    preview = pin_preview(two)
    SiteAssets.invalidate_pinned(two)
    assert served?("assets/acme-two.js", @admin_host)

    Repo.update!(Ecto.Changeset.change(preview, expires_at: ~U[2020-01-01 00:00:00Z]))
    args = Tenant.with_prefix(Tenant.prefix("acme", "production"), fn -> Tenant.Job.attach(%{"id" => preview.id}) end)
    assert :ok = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: args})
    refute served?("assets/acme-two.js", @admin_host)
  end

  test "a suspended or archived site's sets do not answer", %{acme: acme} do
    assert served?("assets/acme-one.js", @admin_host)

    acme =
      Enum.reduce([:suspended, :archived], acme, fn status, site ->
        {:ok, site} = Registry.update_site(site, %{status: status})
        refute served?("assets/acme-one.js", @admin_host), "#{status}"
        site
      end)

    {:ok, _site} = Registry.update_site(acme, %{status: :active})
    assert served?("assets/acme-one.js", @admin_host)
  end

  test "a set another node activates or pins answers here once this node hears of it", %{acme: acme} do
    assert served?("assets/acme-one.js", @admin_host)
    two = register(acme, "acme-two")
    three = register(acme, "acme-three")

    # Another node switches the active set
    Repo.update_all(SiteAssetSet, [set: [active: false]], prefix: "public")
    two |> SiteAssetSet.changeset(%{active: true}) |> Repo.update!(prefix: "public")
    refute served?("assets/acme-two.js", @admin_host)

    SiteAssets.refresh_node_cache({:active, {:site_id, acme.id}})
    assert served?("assets/acme-two.js", @admin_host)
    refute served?("assets/acme-one.js", @admin_host)

    # Another node shares a preview pinned to a set
    pin_preview(three)
    refute served?("assets/acme-three.js", @admin_host)

    SiteAssets.refresh_node_cache({:pinned, {:site_id, acme.id}})
    assert served?("assets/acme-three.js", @admin_host)
  end

  defp page, do: %Page{title: "About", uri: "about", template: "default.html", language: :en, entry_blocks: []}

  defp register(site, name) do
    path = SiteAssetsFixtures.create_set(site, name, "js-#{name}", "#{name}.css")
    File.write!(Path.join(path, "favicon.ico"), "icon-#{name}")
    {:ok, set} = SiteAssets.register_set(site, path, %{})
    set
  end

  defp activate(site, name) do
    {:ok, set} = site |> register(name) |> Map.fetch!(:id) |> SiteAssets.activate_set()
    set
  end

  defp pin_preview(set) do
    user = Brando.Factory.insert(:random_user, avatar: nil)

    Repo.insert!(
      %Preview{
        creator_id: user.id,
        preview_key: Ecto.UUID.generate(),
        html: Brando.Utils.term_to_binary("<main>Pinned</main>"),
        expires_at: DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second),
        asset_set_id: set.id
      },
      prefix: "public"
    )
  end

  defp asset_paths(html) do
    ~r{(?:src|href)="/(assets/[^"]+)"}
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp assert_served(html, host, asset_set) do
    for path <- asset_paths(html) do
      assert body(path, host) == File.read!(Path.join(asset_set.path, path)), path
    end
  end

  defp body(path, host) do
    served = call(path, host)
    assert served.halted, "expected #{path} to be served on #{host}"
    assert served.status == 200
    assert get_resp_header(served, "cache-control") == ["public, max-age=31536000, immutable"]
    served.resp_body
  end

  defp served?(path, host), do: call(path, host).halted

  defp call(path, host) do
    :get
    |> Plug.Test.conn("https://#{host}/#{path}")
    |> Map.put(:host, host)
    |> Brando.Plug.SiteAssets.call([])
  end

  defp reset_caches do
    SiteAssets.invalidate_cache()

    for prefix <- [nil, "tenant_acme_production", "tenant_beta_production"],
        name <- ["cache_manifest", "critical_css"] do
      :persistent_term.erase(Tenant.cache_key({:vite, name}, prefix))
    end
  end
end
