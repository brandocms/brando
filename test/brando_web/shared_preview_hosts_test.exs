defmodule BrandoWeb.SharedPreviewHostsTest do
  # Which hosts open a shared preview's link (`/__p__/:key`), through a
  # router as an installation generates it
  use Brando.ConnCase, async: false

  alias Brando.Assets.SiteAssets.Retention
  alias Brando.SiteAssetsFixtures
  alias Brando.Sites.Preview
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Test.SiteRouter, as: Router

  @admin_host "admin.test"

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    # No environment holds a domain yet
    {:ok, acme} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, production} =
      Registry.create_environment(acme, %{name: "Production", key: "production", live: true}, actor: :system)

    {:ok, staging} = Registry.create_environment(acme, %{name: "Staging", key: "staging"}, actor: :system)
    {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "beta", "beta.test")
    user = Brando.Factory.insert(:random_user, avatar: nil)

    %{acme: Registry.get_site(acme.id), production: production, staging: staging, beta: beta, user: user}
  end

  test "the admin's host opens a preview under the site and environment it was shared from", context do
    key = insert_preview(context.user, site_id: context.acme.id, environment_id: context.staging.id)

    conn = get_preview(key, @admin_host)
    assert conn.status == 200
    assert conn.resp_body =~ "Shared"
    assert conn.assigns.current_site.id == context.acme.id
    assert conn.assigns.current_environment.id == context.staging.id
    assert conn.assigns.tenant_prefix == "tenant_acme_staging"
  end

  test "another site's host does not open a preview, its own does", context do
    site_404_page()
    acme_key = insert_preview(context.user, site_id: context.acme.id, environment_id: context.production.id)
    assert get_preview(acme_key, "beta.test").status == 404

    beta_key = insert_preview(context.user, site_id: context.beta.id)
    assert get_preview(beta_key, "beta.test").status == 200
    assert get_preview(beta_key, @admin_host).status == 200
  end

  test "a preview stored before previews recorded their site", context do
    site_404_page()
    # Its pinned set gave it a site (brando_227): it opens under that site's
    # live environment
    key = insert_preview(context.user, site_id: context.acme.id)
    conn = get_preview(key, @admin_host)
    assert conn.status == 200
    assert conn.assigns.current_environment.id == context.production.id
    assert get_preview(key, "beta.test").status == 404

    # With neither, it opens where it opened before: on any site's host
    neither = insert_preview(context.user, [])
    assert get_preview(neither, "beta.test").status == 200
    assert get_preview(neither, @admin_host).status == 404
  end

  test "a suspended or archived site's preview does not open", context do
    key = insert_preview(context.user, site_id: context.acme.id, environment_id: context.production.id)
    beta_key = insert_preview(context.user, site_id: context.beta.id)

    for status <- [:suspended, :archived] do
      {:ok, _} = Registry.update_site(Registry.get_site(context.acme.id), %{status: status})
      {:ok, _} = Registry.update_site(Registry.get_site(context.beta.id), %{status: status})

      assert get_preview(key, @admin_host).status == 404, "#{status}"
      assert get_preview(beta_key, @admin_host).status == 404, "#{status}"
      assert get_preview(beta_key, "beta.test").status == 404, "#{status}"
    end
  end

  test "a suspended site's host opens no other site's preview", context do
    key = insert_preview(context.user, site_id: context.acme.id, environment_id: context.production.id)
    {:ok, _} = Registry.update_site(Registry.get_site(context.beta.id), %{status: :suspended})

    # Neither host resolves to a site now
    assert Tenant.Frontend.resolve("beta.test") == nil
    assert get_preview(key, "BETA.test").status == 404
    assert get_preview(key, @admin_host).status == 200
  end

  test "a preview outlives its environment, and opens under the site's live one", context do
    key = insert_preview(context.user, site_id: context.acme.id, environment_id: context.staging.id)
    {:ok, _} = Registry.delete_environment(context.staging)

    conn = get_preview(key, @admin_host)
    assert conn.status == 200
    assert conn.assigns.current_environment.id == context.production.id
  end

  test "an expired or unknown key answers 404 on every host", context do
    site_404_page()

    expired =
      insert_preview(context.user,
        site_id: context.acme.id,
        environment_id: context.production.id,
        expires_at: ~U[2020-01-01 00:00:00Z]
      )

    for key <- [expired, "unknown"], host <- [@admin_host, "beta.test"] do
      assert get_preview(key, host).status == 404, "#{key} on #{host}"
    end
  end

  test "a host with no site lets through only a preview's path, and looks up nothing else", context do
    key = insert_preview(context.user, site_id: context.acme.id, environment_id: context.production.id)
    queries = count_queries()

    for path <- ["/robots.txt", "/sitemaps/x.xml", "/__ssg_preview__/#{key}/index.html"] do
      conn = request(path, @admin_host)
      assert conn.status == 404, path
      assert conn.halted, path
    end

    assert queries.() == 0
    assert get_preview(key, @admin_host).status == 200
    assert queries.() == 2
  end

  test "one site and no tenancy open every preview, as before", context do
    key = insert_preview(context.user, site_id: context.acme.id, environment_id: context.production.id)
    neither = insert_preview(context.user, [])

    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, "acme")

    for key <- [key, neither], host <- [@admin_host, "beta.test"] do
      assert get_preview(key, host).status == 200
    end

    put_test_env(:tenancy_mode, :none)

    for key <- [key, neither] do
      conn = get_preview(key, @admin_host)
      assert conn.status == 200
      refute Map.has_key?(conn.assigns, :current_site)
    end
  end

  test "the purger and retention still find a preview's row", context do
    set_id = asset_set!(context.acme).id

    key =
      insert_preview(context.user,
        site_id: context.acme.id,
        environment_id: context.production.id,
        asset_set_id: set_id
      )

    preview = Repo.get_by!(Preview, preview_key: Preview.hash_key(key))
    assert MapSet.member?(Retention.preview_pinned_set_ids(), set_id)

    args = Tenant.with_prefix(Tenant.prefix("acme", "production"), fn -> Tenant.Job.attach(%{"id" => preview.id}) end)
    assert {:snooze, _} = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: args})

    Repo.update!(Ecto.Changeset.change(preview, expires_at: ~U[2020-01-01 00:00:00Z]))
    assert :ok = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: args})
    refute Repo.get(Preview, preview.id)
    refute MapSet.member?(Retention.preview_pinned_set_ids(), set_id)
  end

  defp insert_preview(user, attrs) do
    key = Brando.Utils.random_string(12)
    expires_at = DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)

    Repo.insert!(
      struct(
        %Preview{
          creator_id: user.id,
          preview_key: Preview.hash_key(key),
          html: Brando.Utils.term_to_binary("<main>Shared</main>"),
          expires_at: expires_at
        },
        attrs
      ),
      prefix: "public"
    )

    key
  end

  defp asset_set!(site) do
    Repo.insert!(
      %Brando.Assets.SiteAssetSet{
        site_id: site.id,
        name: "acme-#{System.unique_integer([:positive])}",
        path: "/nowhere",
        uploaded_at: DateTime.utc_now()
      },
      prefix: "public"
    )
  end

  defmodule ErrorHTML do
    @moduledoc false
    def render("404.html", _assigns), do: "Page not found"
  end

  defmodule ErrorEndpoint do
    @moduledoc false
    def config(:render_errors), do: [formats: [html: ErrorHTML]]
  end

  # What a site's host answers for a key it does not open: the site's 404
  # page, which reads its content schema
  defp site_404_page do
    put_test_env(:use_default_errors, true)
    put_test_env(:endpoint_module, ErrorEndpoint)
    {:ok, tables} = Brando.Environments.StructureCloner.Postgres.tenant_tables("public")
    Brando.MigrationTemplates.create_environment("tenant_beta_production", tables)
  end

  defp get_preview(key, host), do: request("/__p__/#{key}", host)

  defp request(path, host) do
    Tenant.put_prefix(nil)

    :get
    |> Plug.Test.conn("https://#{host}#{path}")
    |> Map.put(:host, host)
    |> Router.call(Router.init([]))
  rescue
    error in Phoenix.Router.NoRouteError -> %{error.conn | status: 404, halted: true}
  after
    Tenant.put_prefix(nil)
  end

  # Queries this process runs from now on
  defp count_queries do
    test = self()
    id = "shared-preview-queries-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :telemetry.attach(
      id,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, _meta, _config -> if self() == test, do: :counters.add(counter, 1, 1) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    fn -> :counters.get(counter, 1) end
  end
end
