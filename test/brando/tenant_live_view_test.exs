defmodule Brando.TenantLiveViewTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.LiveView
  alias Brando.Tenant.Registry

  setup do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, production} =
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    {:ok, preview} =
      Registry.create_environment(site, %{
        name: "Preview",
        key: "preview",
        live: false
      })

    %{site: site, production: production, preview: preview}
  end

  test "resolves the selected site and environment from signed session", context do
    assert {site, environment} =
             LiveView.resolve_context(%{}, %{
               "brando_site_key" => "acme",
               "brando_environment_key" => "preview"
             })

    assert site.id == context.site.id
    assert environment.id == context.preview.id
  end

  test "falls back to the live environment when the selection is missing", context do
    assert {_site, environment} = LiveView.resolve_context(%{}, %{})

    assert environment.id == context.production.id
  end

  test "single mode derives its configured site without a session site key", context do
    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, "acme")

    assert {site, environment} = LiveView.resolve_context(%{}, %{})
    assert site.id == context.site.id
    assert environment.id == context.production.id
  end

  test "none mode has no LiveView tenant context" do
    put_test_env(:tenancy_mode, :none)
    assert LiveView.resolve_context(%{}, %{}) == nil
  end
end
