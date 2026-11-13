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

  test "a shared preview opens on its link's host and loads its pinned set, after another set is activated", %{
    acme: acme,
    acme_set: acme_set
  } do
    user = Brando.Factory.insert(:random_user, avatar: nil)
    Tenant.put_prefix(Tenant.prefix("acme", "production"))
    changeset = page() |> Map.put(:key, "about") |> Ecto.Changeset.change()

    assert {:ok, url, _days} = LivePreview.share(Page, changeset, user, %{}, :site)

    # The link is on the endpoint's host, which belongs to no site
    %URI{host: host, path: "/__p__/" <> key = path} = URI.parse(url)
    assert Frontend.resolve(host) == nil

    activate(acme, "acme-two")
    Tenant.put_prefix(nil)

    # Through a router as an installation generates it
    conn =
      :get
      |> Plug.Test.conn(url)
      |> Map.put(:host, host)
      |> Brando.Test.SiteRouter.call(Brando.Test.SiteRouter.init([]))

    assert conn.status == 200
    assert conn.request_path == path
    assert conn.assigns.current_site.id == acme.id
    assert asset_paths(conn.resp_body) == ["assets/acme-one.css", "assets/acme-one.js"]
    assert_served(conn.resp_body, host, acme_set)

    # The row records where the preview was shared from
    assert %Preview{site_id: site_id, environment_id: environment_id} =
             Repo.get_by!(Preview, [preview_key: Preview.hash_key(key)], prefix: "public")

    assert site_id == acme.id
    assert environment_id == Tenant.Cache.get_env("acme", "production").id
  end

  test "sharing writes a shared row and renders nothing" do
    user = Brando.Factory.insert(:random_user, avatar: nil)
    Tenant.put_prefix(Tenant.prefix("acme", "production"))
    changeset = page() |> Map.put(:key, "about") |> Ecto.Changeset.change()

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _url, _days} = LivePreview.share(Page, changeset, user, %{}, :site)
      refute_enqueued(worker: Brando.Worker.EntryCascade)
    end)
  end

  test "a path no set holds stays unanswered on the admin's host" do
    for path <- ["robots.txt", "assets/missing.js", "assets/acme-one.js/x"] do
      refute served?(path, @admin_host), path
    end
  end

  test "a file outside the manifest answers from an active set, as on the site's own host", %{acme_set: acme_set} do
    # From the build's `public/` directory
    File.mkdir_p!(Path.join(acme_set.path, "fonts"))
    File.write!(Path.join(acme_set.path, "fonts/brand.woff2"), "acme-font")
    SiteAssets.invalidate_cache()

    assert body("fonts/brand.woff2", @admin_host) == "acme-font"
    assert body("favicon.ico", @admin_host) == "icon-acme-one"
  end

  test "a path two sites hold with different content stays unanswered", %{beta: beta, acme_set: acme_set} do
    beta_set = activate(beta, "beta-one")
    # The fonts differ in size; the icons are the same size and differ in content
    write_font(acme_set, "acme")
    write_font(beta_set, "beta, longer")

    refute served?("fonts/brand.woff2", @admin_host)
    refute served?("favicon.ico", @admin_host)

    # Each site's own host still has its own
    assert body("fonts/brand.woff2", "beta.test") == "beta, longer"
    assert served?("assets/acme-one.js", @admin_host)
    assert served?("assets/beta-one.js", @admin_host)
  end

  test "a path two sites hold with the same content answers", %{beta: beta, acme_set: acme_set} do
    beta_set = activate(beta, "beta-one")
    write_font(acme_set, "same")
    write_font(beta_set, "same")

    assert body("fonts/brand.woff2", @admin_host) == "same"
  end

  test "a suspended site's file neither answers nor blocks another site's", %{beta: beta, acme_set: acme_set} do
    beta_set = activate(beta, "beta-one")
    write_font(acme_set, "acme")
    write_font(beta_set, "beta")
    refute served?("fonts/brand.woff2", @admin_host)

    # Suspended after the lookup was filled
    {:ok, beta} = Registry.update_site(beta, %{status: :suspended})
    assert body("fonts/brand.woff2", @admin_host) == "acme"
    assert body("favicon.ico", @admin_host) == "icon-acme-one"

    {:ok, _beta} = Registry.update_site(beta, %{status: :active})
    refute served?("fonts/brand.woff2", @admin_host)
  end

  test "within one site, the active set's file wins over a pinned set's", %{acme: acme} do
    # A build that names a manifest file without a hash
    pinned = register(acme, "acme-pinned", "main.css")
    File.write!(Path.join(pinned.path, "assets/main.css"), "pinned")
    pin_preview(pinned)

    active = activate(acme, "acme-active", "main.css")
    File.write!(Path.join(active.path, "assets/main.css"), "active")
    SiteAssets.invalidate_cache()

    assert body("assets/main.css", @admin_host) == "active"

    assert :ok = SiteAssets.deactivate(acme)
    assert body("assets/main.css", @admin_host) == "pinned"
  end

  test "a lookup that fails to load is not kept" do
    SiteAssets.invalidate_cache()

    Repo.transaction(fn ->
      Repo.query!("ALTER TABLE public.site_asset_sets RENAME TO site_asset_sets_away")
      refute served?("assets/acme-one.js", @admin_host)
      Repo.rollback(:restored)
    end)

    assert served?("assets/acme-one.js", @admin_host)
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

  defp register(site, name, css_file \\ nil) do
    path = SiteAssetsFixtures.create_set(site, name, "js-#{name}", css_file || "#{name}.css")
    File.write!(Path.join(path, "favicon.ico"), "icon-#{name}")
    {:ok, set} = SiteAssets.register_set(site, path, %{})
    set
  end

  defp activate(site, name, css_file \\ nil) do
    {:ok, set} = site |> register(name, css_file) |> Map.fetch!(:id) |> SiteAssets.activate_set()
    set
  end

  defp write_font(asset_set, content) do
    File.mkdir_p!(Path.join(asset_set.path, "fonts"))
    File.write!(Path.join(asset_set.path, "fonts/brand.woff2"), content)
    SiteAssets.invalidate_cache()
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
    # What a host with no site answers changes as other sites' sets do
    cache_control = if Frontend.resolve(host), do: "public, max-age=31536000, immutable", else: "no-cache"
    assert get_resp_header(served, "cache-control") == [cache_control]
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
