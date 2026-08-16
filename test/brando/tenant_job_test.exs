defmodule Brando.TenantJobTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Tenant
  alias Brando.Tenant.Job
  alias Brando.Tenant.Registry

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)

    on_exit(fn -> Tenant.put_prefix(nil) end)

    :ok
  end

  test "attaches and restores tenant context across a job boundary" do
    Tenant.put_prefix("tenant_acme_production")

    assert %{"tenant_prefix" => "tenant_acme_production", image_id: 42} =
             Job.attach(%{image_id: 42})

    Tenant.put_prefix("tenant_beta_staging")

    assert Job.run(%{"tenant_prefix" => "tenant_acme_production"}, fn ->
             Tenant.current_prefix()
           end) == "tenant_acme_production"

    assert Tenant.current_prefix() == "tenant_beta_staging"
  end

  test "cancels tenant jobs whose context is missing or invalid" do
    assert_raise ArgumentError, ~r/require a current tenant prefix/, fn -> Job.attach(%{}) end

    assert Job.run(%{}, fn -> flunk("must not run") end) ==
             {:cancel, :missing_tenant_prefix}

    assert Job.run(%{"tenant_prefix" => "public"}, fn -> flunk("must not run") end) ==
             {:cancel, :invalid_tenant_prefix}
  end

  test "runs maintenance in every environment of active sites" do
    active = create_site("acme", :active)
    suspended = create_site("beta", :suspended)

    create_environment(active, "production", true)
    create_environment(active, "staging", false)
    create_environment(suspended, "production", true)

    assert Job.each_active_environment(:all, fn -> Tenant.current_prefix() end) |> Enum.sort() ==
             ["tenant_acme_production", "tenant_acme_staging"]

    assert Job.each_active_environment(:live, fn -> Tenant.current_prefix() end) ==
             ["tenant_acme_production"]
  end

  test "keeps legacy public-schema behavior when tenancy is disabled" do
    put_test_env(:tenancy_mode, :none)
    Tenant.put_prefix(nil)

    assert Job.attach(%{id: 1}) == %{id: 1}
    assert Job.run(%{}, fn -> :public end) == :public
    assert Job.each_active_environment(:all, fn -> :public end) == [:public]
  end

  test "Oban jobs remain pinned to public while a tenant prefix is active" do
    Tenant.put_prefix("tenant_missing_production")
    assert Brando.Repo.all(Oban.Job) == []
  end

  defp create_site(key, status) do
    {:ok, site} =
      Registry.create_site(%{
        name: String.capitalize(key),
        key: key,
        languages: ["en"],
        default_language: "en",
        status: status,
        delivery_mode: :dynamic
      })

    site
  end

  defp create_environment(site, key, live) do
    {:ok, environment} =
      Registry.create_environment(site, %{
        name: String.capitalize(key),
        key: key,
        live: live
      })

    environment
  end
end
