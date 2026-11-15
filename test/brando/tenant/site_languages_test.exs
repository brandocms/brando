# What a generated `CMS.PageController` reads for `/`: the published homepage
# in the site's default language, and the partials
defmodule Brando.Tenant.SiteLanguagesTest.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    language = Brando.Languages.default_language()

    with {:ok, page} <- Brando.Pages.get_page(%{matches: %{uri: "index", language: language}, status: :published}),
         {:ok, %{"footer" => _footer}} <-
           Brando.Pages.get_fragments(%{filter: %{parent_key: "partials", language: language}}) do
      send_resp(conn, 200, page.rendered_blocks)
    else
      _not_found -> send_resp(conn, 404, "")
    end
  end
end

defmodule Brando.Tenant.SiteLanguagesTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :browser
    get "/", Brando.Tenant.SiteLanguagesTest.PageController, :index
  end
end

defmodule Brando.Tenant.SiteLanguagesTest do
  # Changes a provisioned site's languages, and requests its homepage
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Navigation
  alias Brando.Pages
  alias Brando.Sites.Identity
  alias Brando.Sites.SEO
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup
  alias Brando.Worker.SiteLanguageSeed

  @prefixes ~w(tenant_acme_production tenant_acme_staging)

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  # An application's seeder with the optional callback
  defmodule LanguageReporter do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator), do: Brando.Tenant.Seeder.seed(site, environment, creator)

    @impl true
    def seed_language(_site, _environment, language, creator) do
      send(self(), {:seeded_language, Brando.Tenant.current_prefix(), language, creator.id})
      :ok
    end
  end

  # An application's seeder without it
  defmodule SeedOnly do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator), do: Brando.Tenant.Seeder.seed(site, environment, creator)
  end

  defmodule Failing do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator), do: Brando.Tenant.Seeder.seed(site, environment, creator)

    @impl true
    def seed_language(_site, _environment, _language, _creator), do: {:error, :seed_failed}
  end

  defmodule FailingInStaging do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator), do: Brando.Tenant.Seeder.seed(site, environment, creator)

    @impl true
    def seed_language(_site, %{key: "staging"}, _language, _creator), do: {:error, :seed_failed}

    def seed_language(site, environment, language, creator),
      do: Brando.Tenant.Seeder.seed_language(site, environment, language, creator)
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-site-languages-#{System.unique_integer([:positive])}")

    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    # The seeds and rendering fill caches from rows the sandbox rolls back
    cached = for key <- ~w(identity seo navigation)a, do: {key, Brando.Cache.get(key)}

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      Brando.TenantCaches.clear(@prefixes)
      Enum.each(cached, &restore_cache/1)
    end)

    creator = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)
    {:ok, site} = Setup.create_site(site_attrs(), creator, environments: environments())

    %{creator: creator, site: site}
  end

  describe "a language added to a site" do
    test "gets its starting content in every environment, and the new default answers /", %{
      site: site,
      creator: creator
    } do
      assert request("/", "acme.test").status == 200

      assert {:ok, _site} =
               Registry.update_site(site, %{languages: ["no", "en"], default_language: "no"}, creator: creator)

      for environment <- ~w(production staging) do
        in_environment(environment, fn ->
          assert Brando.Repo.get_by!(Identity, language: :no).name == "Acme"
          assert Brando.Repo.get_by(SEO, language: :no)
          assert Brando.Repo.get_by!(Pages.Page, uri: "index", language: :no).creator_id == creator.id
          assert Brando.Repo.get_by(Pages.Fragment, parent_key: "partials", key: "footer", language: :no)
          assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :no)
        end)
      end

      for host <- ["acme.test", "staging.acme.test"] do
        conn = request("/", host)
        assert conn.status == 200, host
        assert conn.resp_body =~ ~s(b-tpl="hero"), host
      end
    end

    test "with no creator given is seeded as the oldest superuser", %{site: site, creator: creator} do
      assert {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]})

      in_environment("production", fn ->
        assert Brando.Repo.get_by!(Pages.Page, uri: "index", language: :no).creator_id ==
                 Brando.Setup.Account.superuser().id

        assert Brando.Setup.Account.superuser().id <= creator.id
      end)
    end

    test "a second run changes nothing", %{site: site, creator: creator} do
      {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
      before = Enum.map(@prefixes, &snapshot/1)

      for environment <- site.environments do
        assert :ok =
                 perform_job(SiteLanguageSeed, %{
                   "tenant_prefix" => Tenant.prefix(site, environment),
                   "language" => "no",
                   "user_id" => creator.id
                 })
      end

      assert Enum.map(@prefixes, &snapshot/1) == before
    end

    test "content already in that language is left alone", %{site: site, creator: creator} do
      in_environment("production", fn ->
        "no"
        |> String.to_existing_atom()
        |> Brando.Sites.create_default_identity()
        |> Ecto.Changeset.change(name: "Acme Norge")
        |> Brando.Repo.update!()
      end)

      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      in_environment("production", fn ->
        assert [%Identity{name: "Acme Norge"}] = Brando.Repo.all(from(i in Identity, where: i.language == :no))
        assert Brando.Repo.get_by(Pages.Page, uri: "index", language: :no)
      end)
    end

    test "is seeded by an application's seed_language/4", %{site: site, creator: creator} do
      put_test_env(:tenant_seeder, LanguageReporter)
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      for prefix <- @prefixes, do: assert_received({:seeded_language, ^prefix, "no", _creator_id})
      in_environment("production", fn -> refute Brando.Repo.get_by(Identity, language: :no) end)
    end

    test "gets the default content from an application's seeder without seed_language/4", %{
      site: site,
      creator: creator
    } do
      put_test_env(:tenant_seeder, SeedOnly)
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      in_environment("staging", fn -> assert Brando.Repo.get_by(Identity, language: :no) end)
    end

    test "is queued once per environment, after the site row is committed", %{site: site, creator: creator} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _site} =
          Brando.Repo.transaction(fn ->
            {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
            refute_enqueued(worker: SiteLanguageSeed)
            site
          end)

        for prefix <- @prefixes do
          assert_enqueued(
            worker: SiteLanguageSeed,
            args: %{"tenant_prefix" => prefix, "language" => "no", "user_id" => creator.id}
          )
        end

        # Queued again while waiting, it is not added twice
        :ok = SiteLanguageSeed.enqueue(Registry.get_site(site.id), "no", creator)
        assert length(all_enqueued(worker: SiteLanguageSeed)) == 2
      end)
    end

    test "queued again, runs a job waiting to retry now, and queues one beside a discarded one", %{
      site: site,
      creator: creator
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
        [production, staging] = Enum.sort_by(site.environments, &(not &1.live))
        later = DateTime.add(DateTime.utc_now(), 3600)

        job = fn environment ->
          prefix = Tenant.prefix(site, environment)
          from(j in Oban.Job, where: fragment("?->>'tenant_prefix'", j.args) == ^prefix)
        end

        Brando.Repo.update_all(job.(production), [set: [state: "retryable", attempt: 1, scheduled_at: later]],
          prefix: "public"
        )

        Brando.Repo.update_all(job.(staging), [set: [state: "discarded", attempt: 3]], prefix: "public")

        :ok = SiteLanguageSeed.enqueue(site, "no", creator)

        assert [%Oban.Job{state: "retryable", scheduled_at: scheduled_at}] =
                 Brando.Repo.all(job.(production), prefix: "public")

        assert DateTime.compare(scheduled_at, later) == :lt

        assert ~w(discarded scheduled) ==
                 job.(staging) |> Brando.Repo.all(prefix: "public") |> Enum.map(& &1.state) |> Enum.sort()
      end)
    end

    test "a failing environment does not undo the save, and its job errors", %{site: site, creator: creator} do
      put_test_env(:tenant_seeder, Failing)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
        assert site.languages == ["en", "no"]

        assert {:error, :seed_failed} =
                 perform_job(SiteLanguageSeed, %{
                   "tenant_prefix" => "tenant_acme_production",
                   "language" => "no",
                   "user_id" => creator.id
                 })
      end)
    end
  end

  describe "a failing seeding job" do
    # A discarded job is pruned minutes later, and the sites screen loses its
    # error with it: a retryable one stays
    test "is retried for days, with growing gaps, before it is discarded" do
      job = SiteLanguageSeed.new(%{"tenant_prefix" => "tenant_acme_production", "language" => "no"})
      assert Ecto.Changeset.get_field(job, :max_attempts) == 20

      backoffs = for attempt <- 1..19, do: SiteLanguageSeed.backoff(%Oban.Job{attempt: attempt})

      assert Enum.take(backoffs, 3) == [30, 60, 120]
      assert Enum.max(backoffs) == 6 * 3600
      assert List.last(backoffs) == 6 * 3600
      assert Enum.sum(backoffs) > 2 * 24 * 3600
    end
  end

  describe "a language added as the new default" do
    test "is seeded in every environment before the save, so / answers at once", %{site: site, creator: creator} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _site} =
                 Registry.update_site(site, %{languages: ["en", "no"], default_language: "no"}, creator: creator)

        refute_enqueued(worker: SiteLanguageSeed)

        for host <- ["acme.test", "staging.acme.test"] do
          conn = request("/", host)
          assert conn.status == 200, host
          assert conn.resp_body =~ ~s(b-tpl="hero"), host
        end
      end)
    end

    test "fails the save when an environment cannot be seeded, and names it", %{site: site, creator: creator} do
      put_test_env(:tenant_seeder, FailingInStaging)

      assert {:error, changeset} =
               Registry.update_site(site, %{languages: ["en", "no"], default_language: "no"}, creator: creator)

      assert [message] = changeset |> Ecto.Changeset.traverse_errors(&elem(&1, 0)) |> Map.fetch!(:default_language)
      assert message =~ "Staging"

      assert %{languages: ["en"], default_language: "en"} = Registry.get_site(site.id)

      # What the other environment got stays, and the next attempt finishes it
      in_environment("production", fn -> assert Brando.Repo.get_by(Identity, language: :no) end)
      put_test_env(:tenant_seeder, Brando.Tenant.Seeder)
      before = snapshot("tenant_acme_production")

      assert {:ok, _site} =
               Registry.update_site(site, %{languages: ["en", "no"], default_language: "no"}, creator: creator)

      assert snapshot("tenant_acme_production") == before
      in_environment("staging", fn -> assert Brando.Repo.get_by(Identity, language: :no) end)
    end

    test "fails the save at once while an environment is copied, restored or set up", %{site: site, creator: creator} do
      key = Brando.Tenant.Lock.environment_operation_key(site.id)
      conn = lock_elsewhere(key)

      # Released later, so a save that waits for the lock ends, and succeeds
      spawn(fn ->
        Process.sleep(1000)
        Postgrex.query!(conn, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
      end)

      assert {:error, changeset} =
               Registry.update_site(site, %{languages: ["en", "no"], default_language: "no"}, creator: creator)

      assert [message] = changeset |> Ecto.Changeset.traverse_errors(&elem(&1, 0)) |> Map.fetch!(:default_language)
      assert message =~ "busy with a copy, restore or setup"
      assert message =~ "Try again"

      assert %{languages: ["en"], default_language: "en"} = Registry.get_site(site.id)
      in_environment("production", fn -> refute Brando.Repo.get_by(Identity, language: :no) end)
    end
  end

  describe "a language removed from a site" do
    setup %{site: site, creator: creator} do
      {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
      %{site: site}
    end

    test "keeps its entries, and they are used again when it is added back", %{site: site, creator: creator} do
      {:ok, site} = Registry.update_site(site, %{languages: ["en"]}, creator: creator)
      before = snapshot("tenant_acme_production")

      in_environment("production", fn -> assert Brando.Repo.get_by(Pages.Page, uri: "index", language: :no) end)

      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
      assert snapshot("tenant_acme_production") == before
    end

    test "the default goes only with a new default in the same save", %{site: site, creator: creator} do
      {:ok, site} = Registry.update_site(site, %{default_language: "no"}, creator: creator)

      assert {:error, changeset} = Registry.update_site(site, %{languages: ["en"]}, creator: creator)
      assert changeset.errors[:default_language]

      assert {:ok, site} = Registry.update_site(site, %{languages: ["en"], default_language: "en"}, creator: creator)
      assert site.default_language == "en"
    end
  end

  describe "a language added back" do
    setup %{site: site, creator: creator} do
      {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
      %{site: site}
    end

    test "whose homepage and footer were trashed gets neither again", %{site: site, creator: creator} do
      in_environment("production", fn ->
        {:ok, _page} = Brando.Repo.soft_delete(Brando.Repo.get_by!(Pages.Page, uri: "index", language: :no))
        {:ok, _footer} = Brando.Repo.soft_delete(footer(:no))
      end)

      {:ok, site} = Registry.update_site(site, %{languages: ["en"]}, creator: creator)
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      in_environment("production", fn ->
        assert [%{deleted_at: %DateTime{}}] = pages(:no)
        assert [%{deleted_at: %DateTime{}}] = footers(:no)
      end)
    end

    test "whose homepage was renamed gets no second homepage or footer", %{site: site, creator: creator} do
      in_environment("production", fn ->
        Pages.Page
        |> Brando.Repo.get_by!(uri: "index", language: :no)
        |> Ecto.Changeset.change(uri: "home")
        |> Brando.Repo.update!()
      end)

      {:ok, site} = Registry.update_site(site, %{languages: ["en"]}, creator: creator)
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      in_environment("production", fn ->
        assert [%{uri: "home"}] = pages(:no)
        assert [_footer] = footers(:no)
      end)
    end

    test "gets each missing piece on its own", %{site: site, creator: creator} do
      in_environment("production", fn ->
        Brando.Repo.delete!(footer(:no))
        Brando.Repo.delete_all(from(m in Navigation.Menu, where: m.language == :no))
      end)

      {:ok, site} = Registry.update_site(site, %{languages: ["en"]}, creator: creator)
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      in_environment("production", fn ->
        [page] = pages(:no)
        assert [%{page_id: page_id}] = footers(:no)
        assert page_id == page.id
        assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :no)
      end)
    end
  end

  describe "a language added that already has pages" do
    test "gets its identity, SEO, footer and menu, and no demo homepage", %{site: site, creator: creator} do
      in_environment("production", fn ->
        Brando.Repo.insert!(%Pages.Page{
          creator_id: creator.id,
          title: "Om oss",
          uri: "om-oss",
          language: :no,
          template: "default.html",
          status: :draft
        })
      end)

      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      in_environment("production", fn ->
        assert [%{uri: "om-oss"}] = pages(:no)
        assert Brando.Repo.get_by(Identity, language: :no)
        assert Brando.Repo.get_by(SEO, language: :no)
        assert [%{page_id: nil}] = footers(:no)
        assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :no)
      end)

      in_environment("staging", fn -> assert [%{uri: "index"}] = pages(:no) end)
    end
  end

  describe "seeding an added language" do
    test "leaves the shared modules alone, and builds its homepage from those that remain", %{
      site: site,
      creator: creator
    } do
      in_environment("production", fn ->
        {:ok, _hero} = Brando.Repo.soft_delete(Brando.Repo.get_by!(Brando.Content.Module, uid: "brando-default-hero"))
        Brando.Repo.delete!(Brando.Repo.get_by!(Brando.Content.Module, uid: "brando-default-steps"))
      end)

      before = in_environment("production", &modules/0)
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      in_environment("production", fn ->
        assert modules() == before

        page =
          Pages.Page
          |> Brando.Repo.get_by!(uri: "index", language: :no)
          |> Brando.Repo.preload(entry_blocks: [block: :module])

        blocks = Enum.sort_by(page.entry_blocks, & &1.sequence)

        assert Enum.map(blocks, & &1.block.module.uid) ==
                 ~w(brando-default-cards brando-default-tips brando-default-terminal brando-default-closing)

        assert Enum.map(blocks, & &1.sequence) == [0, 1, 2, 3]
      end)
    end

    test "tells the other nodes of the identity and SEO it wrote", %{site: site, creator: creator} do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.CacheSync.topic())
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)

      for prefix <- @prefixes, cache <- [:identity, :seo] do
        assert_received {:brando_cache_sync, _origin, {Brando.Cache, {^cache, ^prefix}}}
      end
    end
  end

  describe "a job for an environment being provisioned or copied" do
    setup %{site: site, creator: creator} do
      {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]}, creator: creator)
      args = %{"tenant_prefix" => "tenant_acme_staging", "language" => "no", "user_id" => creator.id}
      %{site: site, args: args}
    end

    for operation <- [:copy, :provisioning] do
      test "waits for the #{operation} to finish", %{site: site, args: args} do
        key = lock_key(unquote(operation), site)
        conn = lock_elsewhere(key)

        in_environment("staging", fn -> Brando.Repo.delete_all(Identity) end)
        assert {:snooze, _seconds} = perform_job(SiteLanguageSeed, args)
        in_environment("staging", fn -> refute Brando.Repo.get_by(Identity, language: :no) end)

        Postgrex.query!(conn, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
        assert :ok = perform_job(SiteLanguageSeed, args)
        in_environment("staging", fn -> assert Brando.Repo.get_by(Identity, language: :no) end)
      end
    end

    test "gives up waiting after an hour, and fails the attempt", %{site: site, args: args} do
      _conn = lock_elsewhere(Brando.Tenant.Lock.environment_operation_key(site.id))

      assert {:snooze, seconds} = perform_job(SiteLanguageSeed, args)
      snoozes = div(3600, seconds)

      assert {:snooze, _} = perform_job(SiteLanguageSeed, args, meta: %{"snoozed" => snoozes - 1})
      assert {:error, :environment_busy} = perform_job(SiteLanguageSeed, args, meta: %{"snoozed" => snoozes})
    end
  end

  describe "a job for an environment or language that is gone" do
    test "is cancelled", %{site: site, creator: creator} do
      assert {:cancel, :language_removed} =
               perform_job(SiteLanguageSeed, %{
                 "tenant_prefix" => "tenant_acme_production",
                 "language" => "no",
                 "user_id" => creator.id
               })

      assert {:cancel, :environment_gone} =
               perform_job(SiteLanguageSeed, %{
                 "tenant_prefix" => "tenant_acme_gone",
                 "language" => "en",
                 "user_id" => creator.id
               })

      assert site.languages == ["en"]
    end
  end

  defp restore_cache({key, nil}), do: Brando.Cache.del(key)
  defp restore_cache({key, value}), do: Brando.Cache.put(key, value, :infinite)

  # What each seeded table holds in the environment
  defp snapshot(prefix) do
    Tenant.with_prefix(prefix, fn ->
      for schema <- [Identity, SEO, Pages.Page, Pages.Fragment, Navigation.Menu, Brando.Content.Module] do
        schema
        |> Brando.Repo.all()
        |> Enum.map(&{&1.id, &1.updated_at})
        |> Enum.sort()
      end
    end)
  end

  defp lock_key(:copy, site), do: Brando.Tenant.Lock.environment_operation_key(site.id)
  defp lock_key(:provisioning, site), do: Brando.Tenant.Lock.lifecycle_key(site.key)

  # A session of its own, outside the sandbox, holds the lock a copy or
  # provisioning holds while it runs
  defp lock_elsewhere(key) do
    config = Keyword.drop(Brando.Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name])
    {:ok, conn} = Postgrex.start_link(config)
    Postgrex.query!(conn, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [key])
    conn
  end

  defp pages(language), do: Brando.Repo.all(from(p in Pages.Page, where: p.language == ^language))

  defp footers(language),
    do:
      Brando.Repo.all(
        from(f in Pages.Fragment, where: f.parent_key == "partials" and f.key == "footer" and f.language == ^language)
      )

  defp footer(language), do: language |> footers() |> hd()

  defp modules do
    Brando.Content.Module
    |> Brando.Repo.all()
    |> Enum.map(&{&1.id, &1.uid, &1.updated_at, &1.deleted_at})
    |> Enum.sort()
  end

  defp in_environment(key, fun), do: Tenant.with_prefix(Tenant.prefix("acme", key), fun)

  defp request(path, host) do
    Tenant.put_prefix(nil)

    :get
    |> Plug.Test.conn("https://#{host}#{path}")
    |> Map.put(:host, host)
    |> Brando.Tenant.SiteLanguagesTest.Router.call(Brando.Tenant.SiteLanguagesTest.Router.init([]))
  after
    Tenant.put_prefix(nil)
  end

  defp environments do
    [
      %{name: "Production", key: "production", live: true, domain: "acme.test"},
      %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"}
    ]
  end

  defp site_attrs do
    %{
      name: "Acme",
      key: "acme",
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end
end
