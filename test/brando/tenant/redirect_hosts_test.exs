defmodule Brando.Tenant.RedirectHostsTest do
  # An environment's redirect hosts: bound once in the installation, by a
  # superuser, carried with the domain, answered from the cache. Also the
  # LiveView origin check and the noindex header for an environment that is
  # not live.
  use Brando.ConnCase, async: false

  import Plug.Test, only: [conn: 3]

  alias Brando.Environments
  alias Brando.Environments.Environment
  alias Brando.Factory
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Origins
  alias Brando.Tenant.Registry

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Brando.Environments.Schema.create(target_prefix)
  end

  defmodule DevEndpoint do
    def url, do: "http://localhost:4000"
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    Cache.clear()
    on_exit(&Cache.clear/0)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme-hosts",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, production} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    {:ok, staging} = Registry.create_environment(site, %{name: "Staging", key: "staging"})
    %{site: site, production: production, staging: staging}
  end

  defp put_hosts(environment, attrs), do: Registry.update_environment(environment, attrs, actor: :system)

  defp scheme, do: URI.parse(Brando.endpoint().url()).scheme

  defp request(method, url, body \\ nil), do: method |> conn(url, body) |> Brando.Plug.Tenant.call([])

  describe "the changeset" do
    test "hosts are trimmed, lower-cased and listed once", %{production: production} do
      assert {:ok, %{redirect_hosts: ["www.acme.test", "old-acme.test"]}} =
               put_hosts(production, %{
                 domain: "acme.test",
                 redirect_hosts: [" WWW.Acme.test", "old-acme.test", "www.acme.test", ""]
               })
    end

    test "a host follows the rules for a domain", %{production: production} do
      endpoint_host = URI.parse(Brando.endpoint().url()).host

      for host <- ["https://www.acme.test", "www.acme.test/path", "www.acme.test.", endpoint_host] do
        assert {:error, changeset} = put_hosts(production, %{domain: "acme.test", redirect_hosts: [host]})
        assert changeset.errors[:redirect_hosts], host
      end

      assert {:error, changeset} = put_hosts(production, %{domain: "acme.test", redirect_hosts: ["acme.test"]})
      assert changeset.errors[:redirect_hosts]
    end

    test "the domain cannot also be one of its redirect hosts", %{production: production} do
      {:ok, production} = put_hosts(production, %{domain: "acme.test", redirect_hosts: ["www.acme.test"]})

      assert {:error, changeset} = put_hosts(production, %{domain: "WWW.acme.test"})
      assert {message, _opts} = changeset.errors[:domain]
      assert message =~ "both the domain and one of its redirect hosts"
      refute changeset.errors[:redirect_hosts]

      assert {:error, changeset} = put_hosts(production, %{redirect_hosts: ["www.acme.test", "acme.test"]})
      assert {message, _opts} = changeset.errors[:redirect_hosts]
      assert message =~ "both the domain and one of its redirect hosts"
    end

    test "redirect hosts need a domain, and the domain cannot be cleared while they remain", %{production: production} do
      assert {:error, changeset} = put_hosts(production, %{redirect_hosts: ["www.acme.test"]})
      assert changeset.errors[:redirect_hosts]

      {:ok, production} = put_hosts(production, %{domain: "acme.test", redirect_hosts: ["www.acme.test"]})

      assert {:error, changeset} = put_hosts(production, %{domain: nil})
      assert changeset.errors[:domain]

      assert {:ok, %{domain: nil, redirect_hosts: []}} = put_hosts(production, %{domain: nil, redirect_hosts: []})
    end

    test "the database refuses redirect hosts without a domain too", %{production: production} do
      assert_raise Postgrex.Error, ~r/environments_redirect_hosts_need_domain/, fn ->
        Brando.Repo.update_all(
          from(e in Environment, where: e.id == ^production.id),
          [set: [redirect_hosts: ["www.acme.test"]]],
          prefix: "public"
        )
      end
    end

    test "the admin's text takes one host per line or comma-separated" do
      assert Environment.parse_hosts("www.acme.test\nold.test, other.test ,\n\n") ==
               ["www.acme.test", "old.test", "other.test"]

      assert Environment.parse_hosts(nil) == []
    end
  end

  describe "a host is bound once" do
    setup %{production: production} do
      {:ok, production} = put_hosts(production, %{domain: "acme.test", redirect_hosts: ["www.acme.test"]})
      %{production: production}
    end

    test "another environment's redirect host is refused as a redirect host", %{staging: staging} do
      assert {:error, changeset} =
               put_hosts(staging, %{domain: "staging.acme.test", redirect_hosts: ["www.acme.test"]})

      assert changeset.errors[:redirect_hosts]
    end

    test "another environment's redirect host is refused as a domain", %{staging: staging, site: site} do
      assert {:error, changeset} = put_hosts(staging, %{domain: "www.acme.test"})
      assert changeset.errors[:domain]

      assert {:error, changeset} =
               Registry.create_environment(site, %{name: "Other", key: "other", domain: "www.acme.test"}, actor: :system)

      assert changeset.errors[:domain]
    end

    test "another environment's domain is refused as a redirect host", %{staging: staging} do
      assert {:error, changeset} = put_hosts(staging, %{domain: "staging.acme.test", redirect_hosts: ["acme.test"]})
      assert changeset.errors[:redirect_hosts]
    end

    test "another site's hosts are refused as well" do
      {:ok, beta} =
        Registry.create_site(%{name: "Beta", key: "beta-hosts", languages: ["en"], default_language: "en"})

      {:ok, beta_production} = Registry.create_environment(beta, %{name: "Production", key: "production"})

      assert {:error, changeset} =
               put_hosts(beta_production, %{domain: "beta.test", redirect_hosts: ["www.acme.test"]})

      assert changeset.errors[:redirect_hosts]
    end

    test "a released host can be bound again", %{production: production, staging: staging} do
      {:ok, _production} = put_hosts(production, %{redirect_hosts: []})

      assert {:ok, %{redirect_hosts: ["www.acme.test"]}} =
               put_hosts(staging, %{domain: "staging.acme.test", redirect_hosts: ["www.acme.test"]})
    end
  end

  describe "who may bind" do
    test "a non-superuser cannot change redirect hosts", %{site: site, production: production} do
      {:ok, production} = put_hosts(production, %{domain: "acme.test"})
      admin = Factory.insert(:random_user, role: :editor)
      {:ok, _} = Brando.Tenant.Access.grant(admin, site, :admin)

      for actor <- [nil, admin] do
        assert {:error, changeset} =
                 Registry.update_environment(production, %{redirect_hosts: ["www.acme.test"]}, actor: actor)

        assert changeset.errors[:redirect_hosts]
      end

      assert Registry.get_environment(production.id).redirect_hosts == []

      superuser = Factory.insert(:random_user, role: :superuser)

      assert {:ok, %{redirect_hosts: ["www.acme.test"]}} =
               Registry.update_environment(production, %{redirect_hosts: ["www.acme.test"]}, actor: superuser)
    end

    # A data migration or a task: `Brando.pubsub/0` names no running PubSub,
    # and the write runs outside `Brando.Repo.transaction/2`
    test "a write without a PubSub running is not undone by the announce", %{production: production} do
      put_test_env(:app_module, Brando.Tenant.RedirectHostsTest.NoApp)

      assert {:ok, %{domain: "acme.test"}} = put_hosts(production, %{domain: "acme.test"})
      assert Registry.get_environment(production.id).domain == "acme.test"
    end
  end

  describe "the hosts follow the live environment" do
    defp hosts(site), do: Map.new(Registry.list_environments(site), &{&1.key, {&1.domain, &1.redirect_hosts}})

    defp redirects_to(host) do
      case Cache.get_redirect(host) do
        {_site, %Environment{key: key, domain: domain}} -> {key, domain}
        nil -> nil
      end
    end

    test "set_live swaps the redirect hosts with the domain, and back", %{
      site: site,
      production: production,
      staging: staging
    } do
      {:ok, production} = put_hosts(production, %{domain: "acme.test", redirect_hosts: ["www.acme.test"]})
      {:ok, staging} = put_hosts(staging, %{domain: "staging.acme.test", redirect_hosts: ["preview.acme.test"]})

      assert {:ok, %Environment{domain: "acme.test", redirect_hosts: ["www.acme.test"]}} =
               Environments.set_live(staging, creator: :system)

      assert hosts(site) == %{
               "production" => {"staging.acme.test", ["preview.acme.test"]},
               "staging" => {"acme.test", ["www.acme.test"]}
             }

      assert redirects_to("www.acme.test") == {"staging", "acme.test"}
      assert redirects_to("preview.acme.test") == {"production", "staging.acme.test"}

      assert {:ok, _production} = Environments.set_live(production, creator: :system)

      assert hosts(site) == %{
               "production" => {"acme.test", ["www.acme.test"]},
               "staging" => {"staging.acme.test", ["preview.acme.test"]}
             }

      assert redirects_to("www.acme.test") == {"production", "acme.test"}
    end

    test "a restored archive set live takes the redirect hosts the same way", %{
      site: site,
      production: production,
      staging: staging
    } do
      {:ok, _production} = put_hosts(production, %{domain: "acme.test", redirect_hosts: ["www.acme.test"]})
      {:ok, _staging} = Environments.set_live(staging, creator: :system)

      assert {:ok, %Environment{domain: nil, redirect_hosts: []} = restored} =
               Environments.rollback(site, creator: :system)

      assert redirects_to("www.acme.test") == {"staging", "acme.test"}

      assert {:ok, %Environment{domain: "acme.test", redirect_hosts: ["www.acme.test"]}} =
               Environments.set_live(restored, creator: :system)

      assert redirects_to("www.acme.test") == {restored.key, "acme.test"}
      assert %{domain: nil, redirect_hosts: []} = Registry.get_environment(staging.id)
    end
  end

  describe "Brando.Plug.Tenant on a redirect host" do
    setup %{production: production} do
      {:ok, production} =
        put_hosts(production, %{domain: "acme.test", redirect_hosts: ["www.acme.test", "old-acme.test"]})

      %{production: production}
    end

    test "GET and HEAD are redirected with 301, keeping the path and query" do
      conn = request(:get, "http://www.acme.test/about/us?lang=en&page=2")
      assert conn.halted
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["#{scheme()}://acme.test/about/us?lang=en&page=2"]

      conn = request(:head, "http://OLD-ACME.test/")
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["#{scheme()}://acme.test/"]
    end

    test "other methods are redirected with 308" do
      conn = request(:post, "http://www.acme.test/contact?sent=1", %{"name" => "A"})
      assert conn.halted
      assert conn.status == 308
      assert get_resp_header(conn, "location") == ["#{scheme()}://acme.test/contact?sent=1"]
    end

    test "the endpoint URL's port is kept when it is not the scheme's default" do
      put_test_env(:endpoint_module, DevEndpoint)

      conn = request(:get, "http://www.acme.test/about?lang=en")
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["http://acme.test:4000/about?lang=en"]
    end

    test "a Markdown request keeps the path the client asked for" do
      conn =
        :get
        |> conn("http://www.acme.test/about.md?lang=en", nil)
        |> Brando.Plug.Markdown.call(Brando.Plug.Markdown.init([]))
        |> Brando.Plug.Tenant.call([])

      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["#{scheme()}://acme.test/about.md?lang=en"]
    end

    test "a static build's signed context keeps precedence over the redirect", %{site: site, production: production} do
      conn =
        :get
        |> conn("http://www.acme.test/about", nil)
        |> put_req_header(Brando.SSG.Context.header(), Brando.SSG.Context.sign(site, production, nil))
        |> Brando.Plug.Tenant.call([])

      refute conn.halted
      assert conn.assigns.current_environment.id == production.id

      conn =
        :get
        |> conn("http://www.acme.test/about", nil)
        |> put_req_header(Brando.SSG.Context.header(), "forged")
        |> Brando.Plug.Tenant.call([])

      assert conn.status == 301
    end

    test "the domain answers, and a host no environment holds is still 404" do
      conn = request(:get, "http://acme.test/about")
      refute conn.halted
      assert conn.assigns.current_environment.key == "production"

      conn = request(:get, "http://unknown.acme.test/about")
      assert conn.halted
      assert conn.status == 404
    end

    test "a suspended site's redirect hosts answer as its domain does", %{site: site} do
      {:ok, _site} = Registry.update_site(site, %{status: :suspended})

      for host <- ["acme.test", "www.acme.test"] do
        conn = request(:get, "http://#{host}/about")
        assert conn.status == 404, host
      end

      assert Brando.Tenant.Frontend.inactive_site_host?("www.acme.test")
    end
  end

  describe "noindex for an environment that is not live" do
    setup %{production: production, staging: staging} do
      {:ok, _production} = put_hosts(production, %{domain: "acme.test"})
      {:ok, _staging} = put_hosts(staging, %{domain: "staging.acme.test"})
      :ok
    end

    test "in :multi, the live environment carries none and another one does" do
      assert get_resp_header(request(:get, "http://acme.test/"), "x-robots-tag") == []
      assert get_resp_header(request(:get, "http://staging.acme.test/"), "x-robots-tag") == ["noindex, nofollow"]
    end

    test "in :single, the same, also for the live environment answering a host with no domain" do
      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, "acme-hosts")

      assert get_resp_header(request(:get, "http://acme.test/"), "x-robots-tag") == []
      assert get_resp_header(request(:get, "http://localhost/"), "x-robots-tag") == []
      assert get_resp_header(request(:get, "http://staging.acme.test/"), "x-robots-tag") == ["noindex, nofollow"]
    end
  end

  describe "Brando.Tenant.Origins" do
    setup %{production: production} do
      {:ok, production} = put_hosts(production, %{domain: "acme.test", redirect_hosts: ["www.acme.test"]})
      %{production: production}
    end

    test "accepts the installation's hosts and a site's domain, not a redirect host or an unknown host" do
      endpoint_host = URI.parse(Brando.endpoint().url()).host

      assert Origins.allowed?(URI.parse("https://#{endpoint_host}"))
      assert Origins.allowed?(URI.parse("https://acme.test"))
      assert Origins.allowed?(URI.parse("https://ACME.test:8443"))
      refute Origins.allowed?(URI.parse("https://www.acme.test"))
      refute Origins.allowed?(URI.parse("https://unknown.test"))
      refute Origins.allowed?(URI.parse("null"))
    end

    test "a domain added later is accepted once it is bound", %{staging: staging} do
      refute Origins.allowed?(URI.parse("https://new.acme.test"))
      {:ok, _staging} = put_hosts(staging, %{domain: "new.acme.test"})
      assert Origins.allowed?(URI.parse("https://new.acme.test"))
    end

    test "takes further origins in the forms Phoenix's check_origin list does" do
      origins = ["//*.agency.example", "https://admin.example.org:8443"]

      assert Origins.allowed?(URI.parse("https://cms.agency.example"), origins)
      assert Origins.allowed?(URI.parse("http://agency.example"), origins)
      assert Origins.allowed?(URI.parse("https://admin.example.org:8443"), origins)
      refute Origins.allowed?(URI.parse("http://admin.example.org:8443"), origins)
      refute Origins.allowed?(URI.parse("https://admin.example.org"), origins)
    end

    test "raises for a further origin with no host, as Phoenix does for its list" do
      for origin <- ["agency.example", "https:", ""] do
        assert_raise ArgumentError, ~r/#{Regex.escape(inspect(origin))}.*\/\/example\.com/s, fn ->
          Origins.allowed?(URI.parse("https://attacker.test"), [origin])
        end
      end
    end
  end
end
