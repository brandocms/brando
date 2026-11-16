defmodule E2E.MultiSiteHosts do
  @moduledoc """
  Two sites whose environments are bound to hosts in every served-hosts
  state, for screenshots of the environments and sites screens. Needs a
  server started with `BRANDO_E2E_MULTI_SITE=1` (`config/e2e.exs`), which
  turns on multi-site tenancy and the served hosts file with this module as
  its resolver. Runs inside the screenshot's sandbox, like any fixture.

  Acme, which the admin opens on, has a served domain and redirect hosts
  that are served, waiting for DNS and not resolving; a staging domain
  waiting for DNS with a redirect host that is not a full host name; and an
  environment with no domain, and three entries in its operation log. Beta has a redirect host stored with a
  trailing dot, which is never served, and a long staging domain that does
  not resolve.

  Options: `:site_admin` makes the E2E admin a site administrator of Acme
  instead of a superuser, who sees the hosts but may not change them;
  `:unwritable` adds a host the file cannot take, so it is "not in the file
  yet" and the screen shows the file's error.
  """

  @behaviour Brando.Tenant.ServedHosts.Resolver

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry, ServedHosts}

  @server {203, 0, 113, 10}
  @elsewhere {198, 51, 100, 24}

  @impl Brando.Tenant.ServedHosts.Resolver
  def lookup(host)
      when host in ~w(acme.example.com www.acme.example.com shop.acme.example.com beta.example.com www.beta.example.com),
      do: {:ok, [@server]}

  def lookup("acme.example.net"), do: {:ok, [@elsewhere]}

  def lookup("staging.acme.example.com"),
    do: {:ok, [@elsewhere, {0x2001, 0xDB8, 0, 0, 0, 0, 0, 0x24}]}

  def lookup(_host), do: {:error, :nxdomain}

  def setup(admin, opts \\ []) do
    unless Tenant.mode() == :multi and ServedHosts.enabled?() do
      raise "the multi-site-hosts fixture needs a server started with BRANDO_E2E_MULTI_SITE=1"
    end

    reset_file()
    # Sites cached from an earlier sandbox are gone from the database
    Cache.clear()

    acme = site("Acme", "acme")
    beta = site("Beta", "beta")

    acme_hosts = ~w(www.acme.example.com acme.example.net old-acme.example.org)

    acme_live =
      environment(acme, admin, "production", "Production", true, "acme.example.com", acme_hosts)

    acme_staging =
      environment(acme, admin, "staging", "Staging", false, "staging.acme.example.com", [
        "preview"
      ])

    acme_spring = environment(acme, admin, "spring", "Spring redesign", false, nil, [])

    beta_live =
      environment(beta, admin, "production", "Production", true, "beta.example.com", [
        "www.beta.example.com"
      ])

    environment(
      beta,
      admin,
      "staging",
      "Staging",
      false,
      "staging-for-the-autumn-campaign.beta.example.com",
      []
    )

    # Stored before Brando refused a trailing dot: no request names it
    Repo.update_all(
      from(e in Environment, where: e.id == ^beta_live.id),
      [set: [redirect_hosts: ["www.beta.example.com", "beta.example.org."]]],
      prefix: "public"
    )

    for environment <- [acme_live, beta_live], do: create_schema(environment)

    for {environment, operation, note} <- [
          {acme_spring, :create, nil},
          {acme_staging, :copy, "Product texts for the spring campaign, copied from production"},
          {acme_live, :set_live, nil}
        ] do
      Repo.insert!(
        %Brando.Environments.OperationLog{
          site_id: acme.id,
          target_environment_id: environment.id,
          creator_id: admin.id,
          operation: operation,
          note: note
        },
        prefix: "public"
      )
    end

    Cache.warm()
    ServedHosts.check()

    if opts[:unwritable] do
      # In the file already, then a host the file cannot take
      File.chmod!(Path.dirname(file()), 0o555)

      Repo.update_all(
        from(e in Environment, where: e.id == ^acme_live.id),
        [set: [redirect_hosts: acme_hosts ++ ["shop.acme.example.com"]]],
        prefix: "public"
      )

      Cache.warm()
      ServedHosts.check()
    end

    if opts[:site_admin] do
      admin = admin |> Ecto.Changeset.change(role: :admin) |> Repo.update!()
      {:ok, _} = Access.grant(admin, acme, :admin)
      admin
    else
      admin
    end
  end

  defp file, do: Application.fetch_env!(:brando, ServedHosts)[:file]

  defp reset_file do
    dir = Path.dirname(file())
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o755)
    File.rm_rf!(file())
  end

  defp site(name, key) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    site
  end

  defp environment(site, admin, key, name, live, domain, redirect_hosts) do
    {:ok, environment} =
      Registry.create_environment(
        site,
        %{name: name, key: key, live: live, domain: domain, redirect_hosts: redirect_hosts},
        actor: admin
      )

    environment
  end

  # The admin enters a site's live environment, whose schema has to hold the
  # application's tables: a copy of the seeded ones
  defp create_schema(environment) do
    prefix = Tenant.prefix(Registry.get_site(environment.site_id), environment)
    Ecto.Adapters.SQL.query!(E2eProject.Repo, ~s(CREATE SCHEMA "#{prefix}"))

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        E2eProject.Repo,
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
      )

    rows
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")

      Ecto.Adapters.SQL.query!(
        E2eProject.Repo,
        ~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|
      )

      Ecto.Adapters.SQL.query!(
        E2eProject.Repo,
        ~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}")
      )
    end)
  end
end
