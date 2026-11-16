defmodule E2E.MultiSiteHosts do
  @moduledoc """
  Two sites whose environments are bound to hosts in every served-hosts
  state, for screenshots of the environments and sites screens. Needs a
  server started with `BRANDO_E2E_MULTI_SITE=1` (`config/e2e.exs`), which
  turns on multi-site tenancy and the served hosts file with this module as
  its resolver. Runs inside the screenshot's sandbox, like any fixture.

  Acme, which the admin opens on, has a served domain and redirect hosts
  that are served, waiting for DNS and not resolving; a staging domain
  waiting for DNS with a redirect host that is not a full host name; an
  environment with no domain; an environment with a key of 30 characters
  and no hyphen, a domain of 60 characters and a longer redirect host, none
  of them resolving; and three entries in its operation log. Beta has a
  redirect host stored with a trailing dot, which is never served, and a
  long staging domain that does not resolve.

  Options: `:site_admin` makes the E2E admin a site administrator of Acme
  instead of a superuser, who sees the hosts but may not change them;
  `:unwritable` adds a host the file cannot take, so it is "not in the file
  yet" and the screen shows the file's error. `:static` makes Acme a static
  site the installation serves itself (the deploy strategy `:local`), for the
  publishing screen; `:published` adds three builds to it, the newest
  deployed and so published, with a ready one before it and one whose three
  URLs failed. `:queued` adds Norwegian to Acme and schedules a copy from
  its production to its staging environment for tomorrow, with Oban in
  manual mode, so the sites screen shows the seeding queued and the
  environments screen the pending copy.
  """

  @behaviour Brando.Tenant.ServedHosts.Resolver

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry, ServedHosts}
  alias Ecto.Adapters.SQL

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

    environment(
      acme,
      admin,
      "autumncampaignlandingpages2026",
      "Autumn campaign",
      false,
      "autumn-campaign-landing-pages-for-the-north.acme.example.com",
      ["www.autumn-campaign-landing-pages-for-the-north.acme.example.com"]
    )

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

    if opts[:static] || opts[:published], do: serve_statically(acme, acme_live, admin, opts[:published])

    if opts[:queued], do: queue(acme, acme_live, acme_staging, admin)

    if opts[:site_admin] do
      admin = admin |> Ecto.Changeset.change(role: :admin) |> Repo.update!()
      {:ok, _} = Access.grant(admin, acme, :admin)
      admin
    else
      admin
    end
  end

  @doc """
  Makes the served hosts file's folder writable again after the
  `:unwritable` fixture, so the next fixture of any kind finds it as the
  server left it. `scripts/server.sh stop` does the same and removes the
  folder. Does nothing on a server started without `BRANDO_E2E_MULTI_SITE=1`.
  """
  def restore_file_dir do
    with config when is_list(config) <- Application.get_env(:brando, ServedHosts),
         file when is_binary(file) <- config[:file],
         true <- File.dir?(Path.dirname(file)) do
      File.chmod!(Path.dirname(file), 0o755)
    end

    :ok
  end

  defp serve_statically(site, live, admin, published?) do
    {:ok, site} =
      Registry.update_site(site, %{
        delivery_mode: :static,
        deploy_config: %{strategy: :local, retention_count: 10}
      })

    if published? do
      ready = build(site, live, admin)

      {:ok, _failed} =
        Brando.SSG.Builds.update(build(site, live, admin, false), %{
          status: :failed,
          built_at: DateTime.utc_now(),
          url_count: 3,
          # A failed build stores the URLs it wrote
          processed_urls: 0,
          failed_urls: ["/ (HTTP 500)", "/about (HTTP 500)", "/contact (HTTP 500)"],
          build_log: "Build failed: 3 URLs failed\n"
        })

      {:ok, _deployed} = Brando.SSG.Deploy.deploy(build(site, live, admin), creator: admin)
      ready
    end

    Cache.warm()
  end

  # Jobs the inline Oban of the E2E server would run at once
  defp queue(site, live, staging, admin) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _site} = Registry.update_site(Registry.get_site(site.id), %{languages: ["en", "no"]})

      {:ok, _job} =
        Brando.Environments.schedule_copy(live, staging, DateTime.add(DateTime.utc_now(), 1, :day), creator: admin)
    end)

    Cache.warm()
  end

  # A build with a page, ready to deploy
  defp build(site, environment, admin, ready? \\ true) do
    {:ok, build} = Brando.SSG.Builds.request_build(Registry.get_site(site.id), environment, creator: admin)
    File.mkdir_p!(build.build_path)
    File.write!(Path.join(build.build_path, "index.html"), "<h1>Acme</h1>")

    if ready? do
      {:ok, ready} =
        Brando.SSG.Builds.update(build, %{
          status: :ready,
          built_at: DateTime.utc_now(),
          file_count: 24,
          total_size: 182_000,
          url_count: 12,
          processed_urls: 12
        })

      ready
    else
      build
    end
  end

  defp file, do: Application.fetch_env!(:brando, ServedHosts)[:file]

  defp reset_file do
    File.mkdir_p!(Path.dirname(file()))
    restore_file_dir()
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
    SQL.query!(E2eProject.Repo, ~s(CREATE SCHEMA "#{prefix}"))

    %{rows: rows} =
      SQL.query!(
        E2eProject.Repo,
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
      )

    rows
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")

      SQL.query!(
        E2eProject.Repo,
        ~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|
      )

      SQL.query!(
        E2eProject.Repo,
        ~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}")
      )
    end)
  end
end
