defmodule Brando.Tenant.SeederTest do
  use Brando.ConnCase, async: true

  alias Brando.Environments.Environment
  alias Brando.Sites.Identity
  alias Brando.Sites.Site
  alias Brando.Tenant

  @prefix "tenant_seeder-acme_production"

  setup do
    put_test_env(:tenancy_mode, :multi)
    Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))

    for table <- ~w(sites_identities sites_seos) do
      Repo.query!(~s|CREATE TABLE "#{@prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
    end

    :ok
  end

  test "names each language's identity after the site" do
    site = %Site{key: "seeder-acme", name: "Acme Site", languages: ["en", "no"]}

    identities =
      Tenant.with_prefix(@prefix, fn ->
        assert :ok = Brando.Tenant.Seeder.seed(site, %Environment{}, %Brando.Users.User{})
        Brando.Repo.all(Identity)
      end)

    assert identities |> Enum.map(&{&1.language, &1.name}) |> Enum.sort() == [en: "Acme Site", no: "Acme Site"]
  end
end
