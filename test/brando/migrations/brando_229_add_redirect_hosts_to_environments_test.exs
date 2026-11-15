defmodule Brando.Migrations.AddRedirectHostsToEnvironmentsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  alias Brando.SiteAssetsFixtures

  @file_name "brando_229_add_redirect_hosts_to_environments.exs"

  defp column?,
    do:
      rows(
        "SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'environments' AND column_name = 'redirect_hosts'",
        []
      ) != []

  # An environment from before the column has no redirect hosts
  test "adds an empty list for every environment and binds each host once, and rolls back" do
    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")
    query!("ALTER TABLE public.environments DROP COLUMN redirect_hosts CASCADE")
    query!("DROP FUNCTION public.brando_environment_hosts_bound_once()")

    version = up(@file_name)

    assert rows("SELECT redirect_hosts FROM public.environments WHERE site_id = $1", [acme.id]) == [[[]]]

    # The site's domain is refused as another environment's redirect host
    assert_raise Postgrex.Error, ~r/environments_redirect_hosts_bound_once/, fn ->
      BrandoIntegration.Repo.transaction(fn ->
        query!(
          "INSERT INTO public.environments (site_id, name, key, live, domain, redirect_hosts, inserted_at, updated_at) " <>
            "VALUES (#{acme.id}, 'Other', 'other', false, 'other.test', '{acme.test}', now(), now())"
        )
      end)
    end

    down(@file_name, version)

    refute column?()
    assert rows("SELECT 1 FROM pg_proc WHERE proname = 'brando_environment_hosts_bound_once'", []) == []
  end
end
