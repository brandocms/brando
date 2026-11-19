defmodule Brando.Tenant.SiteDeployTargetsTest do
  # A site's own allowed deploy targets decide whose directories its deploys
  # may replace, with the server's SSH identity or the installation's S3
  # credentials. Only a superuser (or :system) sets them; nothing a site
  # administrator reaches can.
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup

  @rsync "deploy@static.example.test:/srv/sites/acme"
  @s3 "s3://acme-www"

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(DeployConfig, [])
    Cache.clear()
    on_exit(&Cache.clear/0)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static
      })

    %{site: site, superuser: Factory.insert(:random_user, role: :superuser)}
  end

  defp targets(site) do
    site = Registry.get_site(site.id)
    {site.allowed_rsync_targets, site.allowed_s3_targets}
  end

  defp site_admin(site) do
    user = Factory.insert(:random_user, role: :user)
    {:ok, _grant} = Access.grant(user, site, :admin)
    user
  end

  describe "update_site_deploy_targets/3" do
    test "a superuser or :system sets them", %{site: site, superuser: superuser} do
      assert {:ok, %Site{allowed_rsync_targets: [@rsync], allowed_s3_targets: [@s3]}} =
               Registry.update_site_deploy_targets(
                 site,
                 %{allowed_rsync_targets: [" #{@rsync} ", "", @rsync], allowed_s3_targets: [@s3]},
                 superuser
               )

      assert targets(site) == {[@rsync], [@s3]}

      assert {:ok, _site} = Registry.update_site_deploy_targets(site, %{"allowed_s3_targets" => []}, :system)
      assert targets(site) == {[@rsync], []}
    end

    test "anyone else is refused", %{site: site} do
      for actor <- [nil, site_admin(site), Factory.insert(:random_user, role: :admin)] do
        assert {:error, changeset} = Registry.update_site_deploy_targets(site, %{allowed_s3_targets: [@s3]}, actor)
        assert [allowed_rsync_targets: {message, _opts}] = changeset.errors
        assert message =~ "Only a superuser"
      end

      assert targets(site) == {[], []}
    end

    test "each entry is checked as a config entry is, and names the entry", %{site: site} do
      assert {:error, changeset} =
               Registry.update_site_deploy_targets(
                 site,
                 %{
                   allowed_rsync_targets: [@rsync, "deploy@localhost:/srv/www", "/srv/local"],
                   allowed_s3_targets: ["s3://bucket/a/../b", "s3://bucket/sites/{site_key}"]
                 },
                 :system
               )

      errors = for {field, {_message, opts}} <- changeset.errors, do: {field, opts[:entry]}

      assert Enum.sort(errors) == [
               allowed_rsync_targets: "/srv/local",
               allowed_rsync_targets: "deploy@localhost:/srv/www",
               allowed_s3_targets: "s3://bucket/a/../b",
               allowed_s3_targets: "s3://bucket/sites/{site_key}"
             ]

      assert Enum.any?(changeset.errors, fn {_field, {message, opts}} ->
               opts[:entry] == "s3://bucket/sites/{site_key}" and message =~ "already belongs to this site"
             end)

      assert targets(site) == {[], []}
    end

    test "a list is kept to 50 entries", %{site: site} do
      entries = for n <- 1..51, do: "s3://acme-#{n}"
      assert {:error, changeset} = Registry.update_site_deploy_targets(site, %{allowed_s3_targets: entries}, :system)
      assert [allowed_s3_targets: _too_many] = changeset.errors
    end
  end

  describe "nothing a site administrator reaches changes them" do
    setup %{site: site} do
      {:ok, site} = Registry.update_site_deploy_targets(site, %{allowed_s3_targets: [@s3]}, :system)
      %{site: site}
    end

    test "update_site/3 ignores them, with atom or string keys", %{site: site} do
      assert {:ok, _site} =
               Registry.update_site(site, %{
                 name: "Acme Renamed",
                 allowed_rsync_targets: ["deploy@evil.example.test:/srv/"],
                 allowed_s3_targets: ["s3://beta-www"]
               })

      assert {:ok, _site} =
               Registry.update_site(site, %{
                 "allowed_rsync_targets" => ["deploy@evil.example.test:/srv/"],
                 "allowed_s3_targets" => [],
                 "deploy_config" => %{"strategy" => "s3", "target" => @s3}
               })

      assert targets(site) == {[], [@s3]}
      assert Registry.get_site(site.id).deploy_config.target == @s3
    end

    test "Site.changeset/3 casts neither", %{site: site} do
      changeset = Site.changeset(site, %{allowed_rsync_targets: [@rsync], allowed_s3_targets: []}, [])
      refute Map.has_key?(changeset.changes, :allowed_rsync_targets)
      refute Map.has_key?(changeset.changes, :allowed_s3_targets)
    end

    test "a new site starts with none" do
      {:ok, created} =
        Registry.create_site(%{
          name: "Beta",
          key: "beta",
          languages: ["en"],
          default_language: "en",
          delivery_mode: :static,
          allowed_s3_targets: ["s3://beta-www"]
        })

      assert targets(created) == {[], []}
    end

    test "a site's languages change through Setup leaves them", %{site: site, superuser: superuser} do
      assert {:ok, _site} =
               Setup.update_languages(site, %{languages: ["en"], allowed_s3_targets: []}, superuser)

      assert targets(site) == {[], [@s3]}
    end
  end

  describe "the deploy settings are checked against them" do
    setup %{site: site} do
      {:ok, beta} =
        Registry.create_site(%{
          name: "Beta",
          key: "beta",
          languages: ["en"],
          default_language: "en",
          delivery_mode: :static
        })

      {:ok, site} =
        Registry.update_site_deploy_targets(site, %{allowed_s3_targets: ["s3://acme-www", "s3://tree/"]}, :system)

      %{site: site, beta: beta}
    end

    test "a site's own entry allows that site, not another", %{site: site, beta: beta} do
      assert {:ok, _site} = Registry.update_site(site, %{deploy_config: %{strategy: :s3, target: "s3://acme-www"}})
      assert {:ok, _site} = Registry.update_site(site, %{deploy_config: %{strategy: :s3, target: "s3://tree/acme"}})

      assert {:error, changeset} =
               Registry.update_site(beta, %{deploy_config: %{strategy: :s3, target: "s3://acme-www"}})

      assert {message, _opts} = changeset.changes.deploy_config.errors[:target]
      assert message =~ "A superuser sets the site's allowed deploy targets under Sites"

      assert {:error, _changeset} = Registry.update_site(site, %{deploy_config: %{strategy: :s3, target: "s3://tree"}})
    end

    test "as stored, not as a struct read before they changed", %{site: site} do
      stale = site
      {:ok, _site} = Registry.update_site_deploy_targets(site, %{allowed_s3_targets: []}, :system)

      assert {:error, _changeset} =
               Registry.update_site(stale, %{deploy_config: %{strategy: :s3, target: "s3://acme-www"}})

      assert targets(site) == {[], []}
    end
  end
end
