defmodule Brando.TenantRegistryTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  @site_attrs %{
    name: "Acme",
    key: "acme",
    languages: ["en"],
    default_language: "en",
    status: :active,
    delivery_mode: :dynamic
  }

  setup do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()
    on_exit(&Cache.clear/0)
    :ok
  end

  test "site mutations immediately refresh cached registry reads" do
    assert {:ok, %Site{} = site} = Registry.create_site(@site_attrs)
    assert %Site{id: site_id, name: "Acme"} = Cache.get_site("acme")
    assert site_id == site.id

    assert {:ok, %Site{name: "Acme Updated"}} =
             Registry.update_site(site, %{name: "Acme Updated"})

    assert %Site{name: "Acme Updated"} = Cache.get_site("acme")

    assert {:ok, %Site{}} = Registry.delete_site(site)
    refute Cache.get_site("acme")
  end

  test "environment mutations remove stale keys and populate current keys" do
    {:ok, site} = Registry.create_site(@site_attrs)

    assert {:ok, %Environment{} = environment} =
             Registry.create_environment(site, %{
               name: "Production",
               key: "production",
               live: true,
               domain: "OLD.Acme.test"
             })

    assert %Environment{id: environment_id} = Cache.get_env("acme", "production")
    assert environment_id == environment.id
    assert %Environment{id: ^environment_id} = Cache.get_live_env("acme")
    assert {_site, %Environment{id: ^environment_id}} = Cache.get_env_by_domain("old.acme.test")

    assert {:ok, updated_environment} =
             Registry.update_environment(environment, %{
               key: "live",
               domain: "new.acme.test"
             })

    refute Cache.get_env("acme", "production")
    refute Cache.get_env_by_domain("old.acme.test")
    assert %Environment{id: ^environment_id} = Cache.get_env("acme", "live")
    assert {_site, %Environment{id: ^environment_id}} = Cache.get_env_by_domain("new.acme.test")

    assert {:ok, %Environment{}} = Registry.delete_environment(updated_environment)
    refute Cache.get_env("acme", "live")
    refute Cache.get_live_env("acme")
    refute Cache.get_env_by_domain("new.acme.test")
  end

  test "registry reads expose sites and their named environments" do
    {:ok, site} = Registry.create_site(@site_attrs)

    {:ok, environment} =
      Registry.create_environment(site.id, %{
        name: "Staging",
        key: "staging",
        live: false
      })

    assert [%Site{id: site_id, environments: [%Environment{id: environment_id}]}] =
             Registry.list_sites()

    assert site_id == site.id
    assert environment_id == environment.id

    assert %Site{id: ^site_id} = Registry.get_site(site.id)
    assert %Site{id: ^site_id} = Registry.get_site_by_key("acme")
    assert [%Environment{id: ^environment_id}] = Registry.list_environments(site)
    assert %Environment{id: ^environment_id} = Registry.get_environment(environment.id)
    assert %Environment{id: ^environment_id} = Registry.get_environment_by_key(site, "staging")
  end

  test "failed mutations leave the warmed cache intact" do
    {:ok, site} = Registry.create_site(@site_attrs)
    cached_site = Cache.get_site("acme")

    assert {:error, changeset} = Registry.update_site(site, %{key: "Not Safe"})
    assert changeset.errors[:key]
    assert Cache.get_site("acme") == cached_site
  end

  test "environment creation accepts form-style string attributes" do
    {:ok, site} = Registry.create_site(@site_attrs)

    assert {:ok, %Environment{site_id: site_id, key: "preview"}} =
             Registry.create_environment(site, %{
               "name" => "Preview",
               "key" => "preview",
               "live" => false
             })

    assert site_id == site.id
  end
end
