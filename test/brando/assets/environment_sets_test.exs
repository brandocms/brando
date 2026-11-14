defmodule Brando.Assets.EnvironmentSetsTest do
  # An environment may have a frontend asset set of its own, resolved like
  # its frontend module: its own set, else the site's active set (in
  # `:single`, the standalone active set), else the release. Acme has a live
  # Production on acme.test and a Staging on staging.acme.test, and its site
  # set `acme-one` is active.
  use Brando.ConnCase, async: false

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssets.Retention
  alias Brando.Environments
  alias Brando.Environments.Environment
  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Brando.SiteAssetsFixtures
  alias Brando.Sites.Preview
  alias Brando.SSG.Builds
  alias Brando.Tenant
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

  defmodule SchemaCloner do
    @moduledoc false
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Brando.Environments.Schema.create(target_prefix)
  end

  for mode <- [:multi, :single] do
    describe "in #{mode}" do
      setup do
        setup_installation(unquote(mode))
      end

      test "an environment's own set serves and renders on its host; the other environment gets the site's",
           %{staging: staging, next: next, one: one} do
        assert {:ok, %Environment{asset_set_id: next_id}} = SiteAssets.activate_environment_set(next.id, staging)
        assert next_id == next.id

        assert body("assets/acme-next.js", "staging.acme.test") == "js-acme-next"
        refute served?("assets/acme-one.js", "staging.acme.test")
        assert body("assets/acme-one.js", "acme.test") == "js-acme-one"
        refute served?("assets/acme-next.js", "acme.test")

        assert rendered("staging") == ["assets/acme-next.css", "assets/acme-next.js"]
        assert rendered("production") == ["assets/acme-one.css", "assets/acme-one.js"]

        assert SiteAssets.environment_set(staging).id == next.id
        assert SiteAssets.effective_set(scope(one), staging).id == next.id
        assert SiteAssets.effective_set(scope(one), Tenant.Cache.get_env("acme", "production")).id == one.id
      end

      test "clearing an environment's set makes it follow the site's set again", %{staging: staging, next: next} do
        {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)
        assert rendered("staging") == ["assets/acme-next.css", "assets/acme-next.js"]

        assert {:ok, %Environment{asset_set_id: nil}} = SiteAssets.clear_environment_set(staging)

        assert body("assets/acme-one.js", "staging.acme.test") == "js-acme-one"
        refute served?("assets/acme-next.js", "staging.acme.test")
        assert rendered("staging") == ["assets/acme-one.css", "assets/acme-one.js"]
        # Still registered
        assert Repo.get(Brando.Assets.SiteAssetSet, next.id, prefix: "public")
      end

      test "a live preview and a shared preview from the environment use its set", %{staging: staging, next: next} do
        {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)
        user = Brando.Factory.insert(:random_user, avatar: nil)

        Tenant.put_prefix(Tenant.prefix("acme", "staging"))

        assert asset_paths(LivePreview.render(Page, page(), nil, target: :site)) == [
                 "assets/acme-next.css",
                 "assets/acme-next.js"
               ]

        changeset = page() |> Map.put(:key, "about") |> Ecto.Changeset.change()
        assert {:ok, url, _days} = LivePreview.share(Page, changeset, user, %{}, :site)
        "/__p__/" <> key = URI.parse(url).path

        assert %Preview{asset_set_id: asset_set_id, environment_id: environment_id, html: html} =
                 Repo.get_by!(Preview, [preview_key: Preview.hash_key(key)], prefix: "public")

        assert asset_set_id == next.id
        assert environment_id == staging.id
        assert asset_paths(Brando.Utils.binary_to_term(html)) == ["assets/acme-next.css", "assets/acme-next.js"]
      end

      test "a static build uses the set of the environment it builds", %{
        acme: acme,
        staging: staging,
        next: next,
        one: one
      } do
        {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)
        {:ok, acme} = Registry.update_site(acme, %{delivery_mode: :static})
        production = Tenant.Cache.get_env("acme", "production")

        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:ok, staging_build} = Builds.request_build(acme, staging, creator: :system)
          assert {:ok, production_build} = Builds.request_build(acme, production, creator: :system)
          assert staging_build.asset_set_id == next.id
          assert production_build.asset_set_id == one.id
        end)
      end

      test "after a live switch, the production host serves the set the incoming environment had",
           %{staging: staging, next: next} do
        put_test_env(:environment_schema_cloner, SchemaCloner)
        {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)

        assert {:ok, %Environment{live: true, domain: "acme.test"}} = Environments.set_live(staging)

        assert body("assets/acme-next.js", "acme.test") == "js-acme-next"
        refute served?("assets/acme-one.js", "acme.test")
        assert body("assets/acme-one.js", "staging.acme.test") == "js-acme-one"
        # The set stays with its environment
        assert Registry.get_environment(staging.id).asset_set_id == next.id
      end

      test "a copy into the environment and a new environment leave the set alone", %{
        acme: acme,
        staging: staging,
        next: next
      } do
        put_test_env(:environment_schema_cloner, SchemaCloner)
        {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)
        production = Registry.get_environment(Tenant.Cache.get_env("acme", "production").id)
        for environment <- [production, staging], do: Environments.Schema.create(Tenant.prefix(acme, environment))

        assert {:ok, _copied} = Environments.copy_environment(production, staging)
        assert Registry.get_environment(staging.id).asset_set_id == next.id
        assert Registry.get_environment(production.id).asset_set_id == nil

        {:ok, review} = Registry.create_environment(acme, %{name: "Review", key: "review", live: false}, actor: :system)
        assert review.asset_set_id == nil
      end

      test "a set an environment uses survives pruning and refuses deletion", %{acme: acme, staging: staging, next: next} do
        {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)
        scope = scope(acme)

        assert MapSet.member?(Retention.protected_set_ids(scope), next.id)
        assert {:ok, deleted} = Retention.prune_sets(scope, keep: 0)
        refute next.id in Enum.map(deleted, & &1.id)
        assert {:error, :asset_set_protected} = Retention.delete_set(next.id)

        {:ok, _staging} = SiteAssets.clear_environment_set(staging)
        assert {:ok, _deleted} = Retention.delete_set(next.id)
      end

      test "deleting an environment drops its reference and keeps the set", %{staging: staging, next: next} do
        {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)

        assert {:ok, _deleted} = Environments.delete_environment(staging)
        assert Repo.get(Brando.Assets.SiteAssetSet, next.id, prefix: "public")
        refute MapSet.member?(Retention.environment_set_ids(), next.id)
      end

      test "the environment is named by its keys, for deploy tooling", %{staging: staging, next: next} do
        assert {:ok, %Environment{id: staging_id}} = SiteAssets.activate_environment_set(next.id, {"acme", "staging"})
        assert staging_id == staging.id
        assert {:ok, %Environment{asset_set_id: nil}} = SiteAssets.clear_environment_set({"acme", "staging"})
        assert {:error, :environment_not_found} = SiteAssets.clear_environment_set({"acme", "nowhere"})
        assert {:error, :asset_set_not_found} = SiteAssets.activate_environment_set(-1, staging)
      end

      test "two nodes agree after a change", %{staging: staging, next: next} do
        assert body("assets/acme-one.js", "staging.acme.test") == "js-acme-one"
        assert rendered("staging") == ["assets/acme-one.css", "assets/acme-one.js"]

        # Another node gives Staging its own set
        Repo.update_all(Ecto.Query.from(e in Environment, where: e.id == ^staging.id), [set: [asset_set_id: next.id]],
          prefix: "public"
        )

        assert body("assets/acme-one.js", "staging.acme.test") == "js-acme-one"

        SiteAssets.refresh_node_cache({:environment, staging.id, Tenant.prefix("acme", "staging")})
        assert body("assets/acme-next.js", "staging.acme.test") == "js-acme-next"
        assert rendered("staging") == ["assets/acme-next.css", "assets/acme-next.js"]
      end
    end
  end

  describe "in :multi" do
    setup do
      setup_installation(:multi)
    end

    test "a set of another site is refused", %{staging: staging} do
      {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "beta", "beta.test")
      beta_set = register(beta, "beta-one")
      standalone = register(nil, "standalone-one")

      assert {:error, :asset_set_belongs_to_another_site} = SiteAssets.activate_environment_set(beta_set.id, staging)
      assert {:error, :asset_set_belongs_to_another_site} = SiteAssets.activate_environment_set(standalone.id, staging)
      assert Registry.get_environment(staging.id).asset_set_id == nil
    end

    test "on the admin's host an environment's set answers, unless the site's holds other content under its path",
         %{staging: staging, next: next, one: one} do
      {:ok, _staging} = SiteAssets.activate_environment_set(next.id, staging)
      assert body("assets/acme-next.js", @admin_host) == "js-acme-next"
      assert body("assets/acme-one.js", @admin_host) == "js-acme-one"

      write_font(one, "site")
      write_font(next, "staging, longer")
      refute served?("fonts/brand.woff2", @admin_host)

      write_font(next, "site")
      assert body("fonts/brand.woff2", @admin_host) == "site"
    end
  end

  describe "in :single" do
    setup do
      setup_installation(:single)
    end

    test "a set of a site is refused: environments use standalone sets", %{acme: acme, staging: staging} do
      site_set = register(acme, "acme-site")

      assert {:error, :asset_set_belongs_to_another_site} = SiteAssets.activate_environment_set(site_set.id, staging)
    end
  end

  defp setup_installation(mode) do
    root = Path.join(System.tmp_dir!(), "brando-environment-sets-#{System.unique_integer([:positive])}")
    release = Path.join(root, "release")
    File.mkdir_p!(Path.join(release, "assets"))

    put_test_env(:env, :prod)
    put_test_env(:tenancy_mode, mode)
    put_test_env(:site_key, "acme")
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

    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")

    {:ok, staging} =
      Registry.create_environment(acme, %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"},
        actor: :system
      )

    acme = Registry.get_site(acme.id)
    scope = if mode == :multi, do: acme
    {:ok, one} = scope |> register("acme-one") |> Map.fetch!(:id) |> SiteAssets.activate_set()
    next = register(scope, "acme-next")

    %{acme: acme, staging: staging, one: one, next: next}
  end

  # The scope sets belong to: the site in `:multi`, none in `:single`
  defp scope(%Brando.Assets.SiteAssetSet{site_id: nil}), do: nil
  defp scope(%Brando.Assets.SiteAssetSet{site_id: site_id}), do: Registry.get_site(site_id)
  defp scope(%Brando.Sites.Site{} = site), do: if(Tenant.mode() == :multi, do: site)

  defp page, do: %Page{title: "About", uri: "about", template: "default.html", language: :en, entry_blocks: []}

  defp register(site, name) do
    path = SiteAssetsFixtures.create_set(site, name, "js-#{name}", "#{name}.css")
    {:ok, set} = SiteAssets.register_set(site, path, %{})
    set
  end

  defp write_font(asset_set, content) do
    File.mkdir_p!(Path.join(asset_set.path, "fonts"))
    File.write!(Path.join(asset_set.path, "fonts/brand.woff2"), content)
    SiteAssets.invalidate_cache()
  end

  defp rendered(environment_key) do
    Tenant.with_prefix(Tenant.prefix("acme", environment_key), fn ->
      asset_paths(LivePreview.render(Page, page(), nil, target: :site))
    end)
  end

  defp asset_paths(html) do
    ~r{(?:src|href)="/(assets/[^"]+)"}
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp body(path, host) do
    served = call(path, host)
    assert served.halted, "expected #{path} to be served on #{host}"
    assert served.status == 200
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

    for prefix <- [nil, "tenant_acme_production", "tenant_acme_staging", "tenant_acme_review"],
        name <- ["cache_manifest", "critical_css"] do
      :persistent_term.erase(Tenant.cache_key({:vite, name}, prefix))
    end
  end
end
