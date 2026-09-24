defmodule Brando.SEO.AnalyticsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.SEO.Analytics
  alias Brando.SEO.Analytics.Plausible
  alias Brando.SEO.Analytics.SearchConsole

  # The seeded SEO settings' base URL is https://www.domain.tld.
  @host "www.domain.tld"

  setup do
    previous = Application.get_env(:brando, Analytics)
    Brando.Cache.SEO.set()

    on_exit(fn ->
      if previous, do: Application.put_env(:brando, Analytics, previous), else: Application.delete_env(:brando, Analytics)
    end)

    :ok
  end

  defp configure(sources) do
    Application.put_env(:brando, Analytics, sources)
    Brando.Cache.del({:seo_analytics, Analytics.period_days()})
  end

  defp plausible(overrides \\ []) do
    Keyword.merge([api_key: "plausible-key", req_options: [plug: {Req.Test, Plausible}]], overrides)
  end

  defp search_console do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

    credentials =
      Jason.encode!(%{
        "client_email" => "audit@project.iam.gserviceaccount.com",
        "private_key" => pem,
        "token_uri" => "https://oauth2.googleapis.com/token"
      })

    Brando.Cache.del({:seo_search_console_token, "audit@project.iam.gserviceaccount.com"})
    {[credentials: credentials, req_options: [plug: {Req.Test, SearchConsole}]], key}
  end

  defp stub_plausible(results) do
    Req.Test.stub(Plausible, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:plausible, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(body)})
      Req.Test.json(conn, %{"results" => results})
    end)
  end

  # Answers Google's token endpoint after verifying the signed assertion, and
  # the Search Analytics endpoint with `rows`.
  defp stub_search_console(key, rows) do
    {:RSAPrivateKey, _, modulus, public_exponent, _, _, _, _, _, _, _} = key
    public_key = {:RSAPublicKey, modulus, public_exponent}
    test = self()

    Req.Test.stub(SearchConsole, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.host do
        "oauth2.googleapis.com" ->
          %{"assertion" => jwt, "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer"} = URI.decode_query(body)
          [header, claims, signature] = String.split(jwt, ".")

          valid? =
            :public_key.verify(
              header <> "." <> claims,
              :sha256,
              Base.url_decode64!(signature, padding: false),
              public_key
            )

          send(test, {:token_request, valid?, claims |> Base.url_decode64!(padding: false) |> Jason.decode!()})
          Req.Test.json(conn, %{"access_token" => "google-token", "expires_in" => 3600})

        "www.googleapis.com" ->
          send(
            test,
            {:search_request, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(body)}
          )

          Req.Test.json(conn, %{"rows" => rows})
      end
    end)
  end

  describe "Plausible" do
    test "reads visitors per path for the site the SEO base URL names" do
      configure(plausible: plausible())

      stub_plausible([
        %{"metrics" => [10, 14], "dimensions" => ["/about/"]},
        %{"metrics" => [2, 3], "dimensions" => ["/about"]},
        %{"metrics" => [40, 60], "dimensions" => ["/"]}
      ])

      assert Plausible.configured?()
      assert {:ok, pages} = Plausible.page_stats(28)
      assert pages["/about"] == %{visitors: 12, pageviews: 17}
      assert pages["/"] == %{visitors: 40, pageviews: 60}

      assert_received {:plausible, "/api/v2/query", ["Bearer plausible-key"], body}
      assert body["site_id"] == @host
      assert body["dimensions"] == ["event:page"]
      assert [_from, _to] = body["date_range"]
    end

    test "an API error is reported with its message" do
      configure(plausible: plausible(site_id: "example.com"))

      Req.Test.stub(Plausible, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "Invalid API key"})
      end)

      assert Plausible.page_stats(28) == {:error, "HTTP 401: Invalid API key"}
    end

    test "is not configured without a key" do
      configure(plausible: [site_id: "example.com"])
      refute Plausible.configured?()
      refute Analytics.configured?()
    end
  end

  describe "Search Console" do
    test "signs in as the service account and reads figures per path" do
      {config, key} = search_console()
      configure(search_console: config)

      stub_search_console(key, [
        %{"keys" => ["https://#{@host}/about"], "clicks" => 3, "impressions" => 400, "ctr" => 0.0075, "position" => 6.2}
      ])

      assert SearchConsole.target() == "sc-domain:" <> @host
      assert {:ok, pages} = SearchConsole.page_stats(28)

      assert pages["/about"] == %{
               url: "https://#{@host}/about",
               clicks: 3,
               impressions: 400,
               ctr: 0.0075,
               position: 6.2
             }

      assert_received {:token_request, true, claims}
      assert claims["iss"] == "audit@project.iam.gserviceaccount.com"
      assert claims["scope"] == "https://www.googleapis.com/auth/webmasters.readonly"

      assert_received {:search_request, path, ["Bearer google-token"], body}
      assert path == "/webmasters/v3/sites/sc-domain%3A#{@host}/searchAnalytics/query"
      assert body["dimensions"] == ["page"]

      # The token is reused rather than requested again.
      assert {:ok, _} = SearchConsole.page_stats(28)
      refute_received {:token_request, _, _}
    end

    test "top queries for a page filter on its URL, most impressions first" do
      {config, key} = search_console()
      configure(search_console: config)

      stub_search_console(key, [
        %{"keys" => ["brando cms"], "clicks" => 1, "impressions" => 20, "ctr" => 0.05, "position" => 3.0},
        %{"keys" => ["elixir cms"], "clicks" => 4, "impressions" => 90, "ctr" => 0.044, "position" => 2.1}
      ])

      Brando.Cache.del({:seo_analytics_queries, 28, "/about"})
      assert {:ok, [%{query: "elixir cms", impressions: 90}, %{query: "brando cms"}]} = Analytics.top_queries("/about")

      assert_received {:search_request, _path, _auth, body}
      assert body["dimensions"] == ["query"]

      assert [%{"filters" => [%{"dimension" => "page", "operator" => "equals", "expression" => url}]}] =
               body["dimensionFilterGroups"]

      assert url == "https://#{@host}/about"
    end

    test "credentials that are not a service account key are reported" do
      configure(search_console: [credentials: ~s({"type": "authorized_user"}), property: "sc-domain:example.com"])

      assert SearchConsole.page_stats(28) ==
               {:error, "The Search Console credentials are not a service account key"}
    end
  end

  describe "page_stats/1" do
    test "merges both sources by path and caches the result" do
      {config, key} = search_console()
      configure(plausible: plausible(), search_console: config)

      stub_plausible([%{"metrics" => [5, 8], "dimensions" => ["/about"]}])

      stub_search_console(key, [
        %{"keys" => ["https://#{@host}/about/"], "clicks" => 1, "impressions" => 120, "ctr" => 0.008, "position" => 4.0}
      ])

      stats = Analytics.page_stats()
      assert stats.errors == []
      assert Enum.map(stats.sources, & &1.source) == [:plausible, :search_console]
      assert %{visitors: 5, clicks: 1, impressions: 120} = stats.pages["/about"]

      Req.Test.stub(Plausible, fn _conn -> raise "the cache should have answered" end)
      assert Analytics.page_stats() == stats
    end

    test "a failing source is reported next to the other's figures, and not cached" do
      {config, key} = search_console()
      configure(plausible: plausible(), search_console: config)

      Req.Test.stub(Plausible, fn conn -> conn |> Plug.Conn.put_status(500) |> Req.Test.text("down") end)

      stub_search_console(key, [
        %{"keys" => ["https://#{@host}/"], "clicks" => 2, "impressions" => 10, "ctr" => 0.2, "position" => 1.0}
      ])

      stats = Analytics.page_stats()
      assert [{:plausible, "HTTP 500: down"}] = stats.errors
      assert %{clicks: 2} = stats.pages["/"]
      assert Brando.Cache.get({:seo_analytics, Analytics.period_days()}) == nil
    end
  end

  test "paths drop the host, the query string and a trailing slash" do
    assert Analytics.path("https://example.com/a/b/?x=1") == "/a/b"
    assert Analytics.path("/a/") == "/a"
    assert Analytics.path("https://example.com") == "/"
    assert Analytics.path(nil) == nil
  end
end
