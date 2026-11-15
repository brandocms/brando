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
