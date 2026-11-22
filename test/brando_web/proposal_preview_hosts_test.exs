defmodule BrandoWeb.ProposalPreviewHostsTest do
  # Where a connected tool's preview of a proposal (`preview_proposal`, a
  # shared preview with `proposal_id`) opens, through a router as an
  # installation generates it: only while the proposal is under review, and
  # in multi-site mode only under its own site and environment
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals.Record
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
      Registry.create_environment(acme, %{name: "Production", key: "production", live: true, domain: "acme.test"},
        actor: :system
      )

    {:ok, staging} =
      Registry.create_environment(acme, %{name: "Staging", key: "staging", domain: "staging.acme.test"}, actor: :system)

    user = Brando.Factory.insert(:random_user, avatar: nil)
    proposal = insert_proposal(user)
    site_404_page(["tenant_acme_production", "tenant_acme_staging"])

    %{acme: Registry.get_site(acme.id), production: production, staging: staging, user: user, proposal: proposal}
  end

  test "a staging proposal opens on the admin's host and on staging's, not on the live host", c do
    key = insert_preview(c, c.staging)

    conn = get_preview(key, @admin_host)
    assert conn.status == 200
    assert conn.resp_body =~ "Proposed"
    assert conn.assigns.current_environment.id == c.staging.id
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert get_preview(key, "staging.acme.test").status == 200
    assert get_preview(key, "acme.test").status == 404

    # The live environment's own proposal opens on the live host
    live_key = insert_preview(c, c.production)
    assert get_preview(live_key, "acme.test").status == 200
    assert get_preview(live_key, "staging.acme.test").status == 404
  end

  test "opens nowhere once its environment is deleted, where an editor's link falls back to live", c do
    key = insert_preview(c, c.staging)
    editors = insert_preview(c, c.staging, proposal_id: nil)
    {:ok, _} = Registry.delete_environment(c.staging)

    for host <- [@admin_host, "acme.test", "staging.acme.test"] do
      assert get_preview(key, host).status == 404, host
    end

    assert get_preview(editors, @admin_host).status == 200
  end

  test "a proposal's preview stored without its site or environment opens on no host", c do
    keys = [
      insert_preview(c, c.staging, site_id: nil, environment_id: nil),
      insert_preview(c, c.staging, site_id: nil),
      insert_preview(c, c.staging, environment_id: nil)
    ]

    for key <- keys, host <- [@admin_host, "acme.test", "staging.acme.test"] do
      assert get_preview(key, host).status == 404, host
    end

    # An editor's link without a site opens on any site's host, as before
    editors = insert_preview(c, c.staging, site_id: nil, environment_id: nil, proposal_id: nil)

    for host <- ["acme.test", "staging.acme.test"] do
      assert get_preview(editors, host).status == 200, host
    end
  end

  test "opens no more once the proposal is not under review, or has expired", c do
    key = insert_preview(c, c.staging)

    set!(c.proposal, status: "approved")
    assert get_preview(key, @admin_host).status == 200

    for status <- ~w(applied undone superseded cancelled) do
      set!(c.proposal, status: status)

      for host <- [@admin_host, "staging.acme.test"] do
        assert get_preview(key, host).status == 404, "#{status} on #{host}"
      end
    end

    set!(c.proposal, status: "pending", expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    assert get_preview(key, @admin_host).status == 404
  end

  test "one site and no tenancy open it on any host while it is under review", c do
    key = insert_preview(c, c.staging)

    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, "acme")

    for host <- [@admin_host, "acme.test"] do
      conn = get_preview(key, host)
      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    put_test_env(:tenancy_mode, :none)
    conn = get_preview(key, @admin_host)
    assert conn.status == 200
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]

    set!(c.proposal, status: "cancelled")

    for mode <- [:single, :none] do
      put_test_env(:tenancy_mode, mode)
      assert get_preview(key, @admin_host).status == 404, "#{mode}"
    end
  end

  defp insert_proposal(user) do
    Repo.insert!(%Record{
      id: Ecto.UUID.generate(),
      version: 1,
      scope: "acme:staging",
      actor_id: user.id,
      origin: "mcp",
      client: "Claude Code",
      operations: [],
      fingerprints: %{},
      module_versions: [],
      problems: [],
      effects: %{},
      status: "pending",
      expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)
    })
  end

  defp set!(proposal, fields), do: Repo.update_all(from(r in Record, where: r.id == ^proposal.id), set: fields)

  defp insert_preview(c, environment, attrs \\ []) do
    key = Brando.Utils.random_string(12)
    expires_at = DateTime.utc_now() |> DateTime.add(900, :second) |> DateTime.truncate(:second)

    Repo.insert!(
      struct(
        %Preview{
          creator_id: c.user.id,
          preview_key: Preview.hash_key(key),
          html: Brando.Utils.term_to_binary("<main>Proposed</main>"),
          expires_at: expires_at,
          site_id: c.acme.id,
          environment_id: environment.id,
          proposal_id: c.proposal.id
        },
        attrs
      ),
      prefix: "public"
    )

    key
  end

  defmodule ErrorHTML do
    @moduledoc false
    def render("404.html", _assigns), do: "Page not found"
  end

  defmodule ErrorEndpoint do
    @moduledoc false
    def config(:render_errors), do: [formats: [html: ErrorHTML]]
  end

  # What a host answers for a link it does not open: the site's 404 page,
  # which reads its environment's content schema
  defp site_404_page(prefixes) do
    put_test_env(:use_default_errors, true)
    put_test_env(:endpoint_module, ErrorEndpoint)
    {:ok, tables} = Brando.Environments.StructureCloner.Postgres.tenant_tables("public")
    Enum.each(prefixes, &Brando.MigrationTemplates.create_environment(&1, tables))
  end

  defp get_preview(key, host) do
    Tenant.put_prefix(nil)

    :get
    |> Plug.Test.conn("https://#{host}/__p__/#{key}")
    |> Map.put(:host, host)
    |> Router.call(Router.init([]))
  rescue
    error in Phoenix.Router.NoRouteError -> %{error.conn | status: 404, halted: true}
  after
    Tenant.put_prefix(nil)
  end
end
