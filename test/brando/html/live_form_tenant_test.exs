defmodule Brando.HTML.Forms.LiveFormTenantTest.SiteFormLive do
  @moduledoc false
  use Phoenix.LiveView

  on_mount Brando.Tenant.FrontendLiveView

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, Brando.Forms.get_published_form("contact", "en"))
     |> assign(:meta, Brando.HTML.Forms.LiveForm.connect_meta(socket))}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={Brando.HTML.Forms.LiveForm} id="contact" form={@form} meta={@meta}>
      <:success><p>Got it.</p></:success>
    </.live_component>
    """
  end
end

defmodule Brando.HTML.Forms.LiveFormTenantTest.UnhookedFormLive do
  @moduledoc false
  use Phoenix.LiveView

  def mount(_params, %{"form" => form}, socket) do
    {:ok, socket |> assign(:form, form) |> assign(:meta, Brando.HTML.Forms.LiveForm.connect_meta(socket))}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={Brando.HTML.Forms.LiveForm} id="contact" form={@form} meta={@meta}>
      <:success><p>Got it.</p></:success>
    </.live_component>
    """
  end
end

defmodule Brando.HTML.Forms.LiveFormTenantTest do
  # Audit F29: a LiveForm's connected process had no tenant prefix, so its
  # submissions were stored under "public", outside the site's listing and
  # retention purge, with the public schema's copy of the form.
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Brando.Factory
  alias Brando.Forms
  alias Brando.Forms.Submission
  alias Brando.HTML.Forms.LiveFormTenantTest.{SiteFormLive, UnhookedFormLive}
  alias Brando.Tenant
  alias Brando.Tenant.{Cache, Registry}

  setup do
    Forms.RateLimit.reset()
    user = Factory.insert(:random_user)
    # The public schema keeps the copy a tenant migration leaves behind
    {:ok, _legacy} = create_form(user, "LegacyLabel")

    put_test_env(:tenancy_mode, :multi)
    Cache.clear()
    on_exit(&Cache.clear/0)

    key = "liveform-#{System.unique_integer([:positive])}"

    {:ok, site} =
      Registry.create_site(%{name: key, key: key, languages: ["en"], default_language: "en", status: :active})

    {:ok, environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", domain: "#{key}.test", live: true})

    prefix = Tenant.prefix(site, environment)
    Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

    %{rows: rows} = Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    for [table] <- rows, not Tenant.SharedTables.member?(table) do
      Repo.query!(~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
    end

    {:ok, tenant_form} = Tenant.with_prefix(prefix, fn -> create_form(user, "TenantLabel") end)
    Tenant.put_prefix(nil)

    %{host: "#{key}.test", prefix: prefix, tenant_form: tenant_form}
  end

  test "a submission is stored in the page's site", %{conn: conn, host: host, prefix: prefix} do
    {:ok, view, html} = live_isolated(%{conn | host: host}, SiteFormLive)
    assert html =~ "TenantLabel"

    view |> form("#contact-form", %{"fields" => %{"name" => "Ada"}}) |> render_submit()
    assert has_element?(view, "#contact-form-sent.is-shown")

    assert [%Submission{scope: ^prefix, labels: %{"name" => "TenantLabel"}}] = Repo.all(Submission)
    assert [_] = Tenant.with_prefix(prefix, fn -> Forms.list_submissions("contact") end)
  end

  test "a LiveView without the hook does not send the form", %{conn: conn, host: host, tenant_form: form} do
    {:ok, view, _html} = live_isolated(%{conn | host: host}, UnhookedFormLive, session: %{"form" => form})

    view |> form("#contact-form", %{"fields" => %{"name" => "Ada"}}) |> render_submit()
    assert has_element?(view, "#contact-form-failed.is-shown")
    refute has_element?(view, "#contact-form-sent.is-shown")
    assert Repo.all(Submission) == []
  end

  test "a host that resolves no site is not found", %{conn: conn} do
    assert_raise Brando.Exception.EntryNotFoundError, fn ->
      live_isolated(%{conn | host: "unknown.test"}, SiteFormLive)
    end
  end

  defp create_form(user, label) do
    Forms.create_form(
      %{
        "title" => "Contact",
        "key" => "contact",
        "language" => "en",
        "status" => "published",
        "fields" => [%{"key" => "name", "type" => "text", "label" => label, "required" => "true"}]
      },
      user
    )
  end
end
