defmodule Brando.TenantCacheTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache

  setup do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()
    on_exit(&Cache.clear/0)
    :ok
  end

  test "warms site, environment, domain, and live-environment lookups" do
    site = insert_site!("acme")
    environment = insert_environment!(site, "production", true, "www.acme.test")

    assert Cache.warm() == :ok

    assert %Site{id: site_id, environments: [%Environment{id: environment_id}]} =
             Cache.get_site("acme")

    assert site_id == site.id
    assert environment_id == environment.id
    assert %Environment{id: ^environment_id} = Cache.get_env("acme", "production")
    assert %Environment{id: ^environment_id} = Cache.get_live_env("acme")

    assert {%Site{id: ^site_id}, %Environment{id: ^environment_id}} =
             Cache.get_env_by_domain("www.acme.test")
  end

  test "rewarming removes stale lookup keys" do
    site = insert_site!("acme")
    environment = insert_environment!(site, "production", true, "old.acme.test")
    Cache.warm()

    environment
    |> Environment.changeset(%{domain: "new.acme.test"})
    |> Repo.update!()

    Cache.invalidate()

    refute Cache.get_env_by_domain("old.acme.test")
    assert Cache.get_env_by_domain("new.acme.test")
  end

  test "disabled tenancy clears old entries" do
    site = insert_site!("acme")
    insert_environment!(site, "production", true, nil)
    Cache.warm()
    assert Cache.get_site("acme")

    Application.put_env(:brando, :tenancy_mode, :none)

    assert Cache.warm() == :ok
    refute Cache.get_site("acme")
  end

  test "the database enforces one live environment per site" do
    site = insert_site!("acme")
    insert_environment!(site, "production", true, nil)

    assert {:error, changeset} =
             %Environment{}
             |> Environment.changeset(%{
               site_id: site.id,
               name: "Staging",
               key: "staging",
               live: true
             })
             |> Repo.insert()

    assert changeset.errors[:live]
  end

  test "static-site deployment configuration round-trips through the public registry" do
    site =
      %Site{}
      |> Site.changeset(%{
        name: "Static Acme",
        key: "static-acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{
          strategy: :rsync,
          target: "web@example:/srv/acme",
          cdn_url: "https://cdn.acme.test"
        }
      })
      |> Repo.insert!()

    reloaded = Repo.get!(Site, site.id)

    assert reloaded.delivery_mode == :static
    assert reloaded.deploy_config.strategy == :rsync
    assert reloaded.deploy_config.target == "web@example:/srv/acme"
    assert reloaded.deploy_config.cdn_url == "https://cdn.acme.test"
  end

  defp insert_site!(key) do
    %Site{}
    |> Site.changeset(%{
      name: String.capitalize(key),
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    })
    |> Repo.insert!()
  end

  defp insert_environment!(site, key, live, domain) do
    %Environment{}
    |> Environment.changeset(%{
      site_id: site.id,
      name: String.capitalize(key),
      key: key,
      live: live,
      domain: domain
    })
    |> Repo.insert!()
  end
end
