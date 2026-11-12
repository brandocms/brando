defmodule BrandoAdmin.Components.Form.BlockFieldSiteTest do
  # Every element that wraps module markup in the admin carries the selected
  # site's key as `data-site`, which the application's admin stylesheet
  # scopes a site's module rules to, and nothing without a selected site.
  #
  # Not async: it creates a tenant schema and registers a site in the tenant
  # cache, which is the node's.
  use Brando.LiveCase, async: false

  import Phoenix.Component, only: [sigil_H: 2]

  alias Brando.FrontendEditFixtures
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias BrandoAdmin.Components.Form.EntrySkeleton

  @site_key "data-site-acme"
  @prefix "tenant_data-site-acme_production"

  defp tenant_site do
    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: @site_key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    # An environment schema with a copy of every tenant table, inside the
    # test's transaction
    Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))

    "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      Repo.query!(~s|CREATE TABLE "#{@prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      Repo.query!(~s(INSERT INTO "#{@prefix}"."#{escaped}" SELECT * FROM public."#{escaped}"))
    end)

    # Registry writes warm the tenant cache after commit, which the sandbox never does
    Tenant.Cache.warm()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)
  end

  # A page with text blocks at the root, `count` besides two, through
  # `Brando.Repo`, which writes to the process's tenant prefix
  defp page_with_blocks(user, count) do
    module = FrontendEditFixtures.text_module(user)
    source = Brando.Pages.Page.Blocks

    page =
      Brando.Repo.insert!(%Brando.Pages.Page{
        title: "About us",
        uri: Brando.Utils.random_string(8),
        language: :en,
        template: "default.html",
        status: :published,
        creator_id: user.id
      })

    blocks = for n <- 1..(count + 2), do: FrontendEditFixtures.text_block(module, user, source, "Paragraph #{n}")
    FrontendEditFixtures.attach(source, page, blocks)
    {:ok, page} = Brando.Content.Blocks.render_entry(Brando.Pages.Page, page.id)
    page
  end

  defp on_site(conn), do: conn |> post("/admin/environment", %{"site_key" => @site_key}) |> recycle()

  defp wrappers(html), do: html |> Floki.parse_document!() |> Floki.find(".blocks-wrapper")

  describe "with a site selected" do
    setup %{conn: conn, current_user: user} do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :multi)
      tenant_site()

      page = Tenant.with_prefix(@prefix, fn -> page_with_blocks(user, 0) end)
      %{conn: on_site(conn), page: page}
    end

    test "the block editor's wrapper has the site's key", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      assert [_ | _] = wrappers = view |> render() |> wrappers()
      assert Enum.all?(wrappers, &(Floki.attribute(&1, "data-site") == [@site_key]))
    end

    test "the entry editor's loading skeleton has it", %{conn: conn, page: page} do
      html = conn |> get("/admin/pages/update/#{page.id}") |> html_response(200)

      assert [skeleton] = html |> Floki.parse_document!() |> Floki.find(".blocks-wrapper.blocks-loading")
      assert Floki.attribute(skeleton, "data-site") == [@site_key]
    end
  end

  describe "without a site" do
    setup do
      put_test_env(:tenancy_mode, :none)
      :ok
    end

    test "the block editor's wrapper has no data-site", %{conn: conn, current_user: user} do
      page = page_with_blocks(user, 0)
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      assert [_ | _] = wrappers = view |> render() |> wrappers()
      assert Enum.all?(wrappers, &(Floki.attribute(&1, "data-site") == []))
    end

    test "the entry editor's loading skeleton has none", %{conn: conn, current_user: user} do
      page = page_with_blocks(user, 0)
      html = conn |> get("/admin/pages/update/#{page.id}") |> html_response(200)

      assert [skeleton] = html |> Floki.parse_document!() |> Floki.find(".blocks-wrapper.blocks-loading")
      assert Floki.attribute(skeleton, "data-site") == []
    end
  end

  test "a heavy entry's block field skeleton takes the site it is given" do
    for {site, expected} <- [{@site_key, [@site_key]}, {nil, []}] do
      assigns = %{site: site}
      html = rendered_to_string(~H|<EntrySkeleton.blocks count={3} site={@site} />|)
      assert html |> wrappers() |> hd() |> Floki.attribute("data-site") == expected
    end
  end

  describe "a block field render" do
    setup %{conn: conn, current_user: user} do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :multi)
      tenant_site()

      page = Tenant.with_prefix(@prefix, fn -> page_with_blocks(user, 1) end)
      %{conn: on_site(conn), page: page}
    end

    test "does not send the wrapper's data-site again", %{conn: conn, page: page} do
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")
      assert html =~ ~s(data-site="#{@site_key}")

      [wrapper | _] = view |> render() |> wrappers()
      [wrapper_id] = Floki.attribute(wrapper, "id")
      block_field_id = String.replace_suffix(wrapper_id, "-wrapper", "")
      block_field_cid = cid_of(view, "##{wrapper_id}")
      [uid | _] = view |> render() |> Floki.parse_document!() |> Floki.attribute("[data-block-uid]", "data-block-uid")

      {_ref, _topic, proxy} = view.proxy
      :erlang.trace(proxy, true, [:receive])

      try do
        Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form.BlockField,
          id: block_field_id,
          event: "delete_block",
          uid: uid
        )

        refute render(view) =~ ~s(data-block-uid="#{uid}")

        payloads = received_payloads()
        # The delete re-rendered the block field, its wrapper's undo marker too
        assert Enum.any?(payloads, &(inspect(get_in(&1, [:c, block_field_cid])) =~ "data-undo-at"))

        for payload <- payloads do
          # Statics go once, so a re-sent attribute is its value
          refute inspect(payload, limit: :infinity, printable_limit: :infinity) =~ @site_key
        end
      after
        :erlang.trace(proxy, false, [:receive])
      end
    end
  end

  # What the LiveView sent the test's client since tracing began: event
  # replies and pushed diffs.
  defp received_payloads(acc \\ []) do
    receive do
      {:trace, _pid, :receive, %Phoenix.Socket.Reply{payload: payload}} -> received_payloads([payload | acc])
      {:trace, _pid, :receive, %Phoenix.Socket.Message{payload: payload}} -> received_payloads([payload | acc])
      {:trace, _pid, :receive, _other} -> received_payloads(acc)
    after
      100 -> Enum.reverse(acc)
    end
  end
end
