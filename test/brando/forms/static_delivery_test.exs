defmodule Brando.Forms.StaticDeliveryTest do
  use Brando.ConnCase, async: false

  alias Brando.Environments.Environment
  alias Brando.Forms.Delivery
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Cache

  setup do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    static = insert_site!("acme", :static)
    insert_environment!(static, "production", "www.acme.test")
    dynamic = insert_site!("other", :dynamic)
    insert_environment!(dynamic, "production", "www.other.test")
    Cache.warm()
    :ok
  end

  defp insert_site!(key, mode) do
    %Site{}
    |> Site.changeset(%{
      name: String.capitalize(key),
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: mode
    })
    |> Repo.insert!()
  end

  defp insert_environment!(site, key, domain) do
    %Environment{}
    |> Environment.changeset(%{site_id: site.id, name: key, key: key, live: true, domain: domain})
    |> Repo.insert!()
  end

  @stored ~s(<form id="form-contact" action="/__brando/forms/contact" method="post"><input type="hidden" name="_csrf_token" value="$csrftoken"></form>)

  test "a static site posts to the backend, without a token" do
    Tenant.put_prefix("tenant_acme_production")
    action = Brando.endpoint().url() <> "/__brando/forms/static/acme/production/contact"

    assert Delivery.action("contact") == action
    assert Delivery.csrf_token() == nil
    assert Delivery.finalize(@stored) == ~s(<form id="form-contact" action="#{action}" method="post"></form>)
  end

  test "a dynamic site keeps its own route and gets the token" do
    Tenant.put_prefix("tenant_other_production")

    assert Delivery.action("contact") == "/__brando/forms/contact"
    assert Delivery.finalize(@stored) =~ ~s(action="/__brando/forms/contact")
    refute Delivery.finalize(@stored) =~ "$csrftoken"
  end

  describe "the static route" do
    defp post_static(conn, path, origin) do
      conn
      |> put_req_header("accept", "application/json, text/html;q=0.1")
      |> put_req_header("origin", origin)
      |> post(path, %{"fields" => %{}})
    end

    test "refuses a post from another domain", %{conn: conn} do
      conn = post_static(conn, "/__brando/forms/static/acme/production/contact", "https://www.other.test")
      assert json_response(conn, 403) == %{"ok" => false}
    end

    test "refuses a site that is not delivered statically", %{conn: conn} do
      conn = post_static(conn, "/__brando/forms/static/other/production/contact", "https://www.other.test")
      assert json_response(conn, 403) == %{"ok" => false}
    end

    test "refuses an unknown site or environment", %{conn: conn} do
      assert conn
             |> post_static("/__brando/forms/static/nope/production/contact", "https://www.acme.test")
             |> json_response(403)

      assert build_conn()
             |> post_static("/__brando/forms/static/acme/staging/contact", "https://www.acme.test")
             |> json_response(403)
    end
  end
end
