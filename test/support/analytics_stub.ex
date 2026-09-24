defmodule Brando.AnalyticsStub do
  @moduledoc """
  Configures `Brando.SEO.Analytics` with both sources answered by `Req.Test`
  stubs, for LiveView tests. Stubs are shared, the way `Brando.AIStub` shares
  its own, because the audit reads the sources from a `start_async` task.

      Brando.AnalyticsStub.configure(
        pages: %{"/about" => %{visitors: 12, clicks: 3, impressions: 400, ctr: 0.0075, position: 6.2}},
        queries: [%{query: "about us", clicks: 2, impressions: 90, ctr: 0.02, position: 3.1}]
      )
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Brando.SEO.Analytics
  alias Brando.SEO.Analytics.Plausible
  alias Brando.SEO.Analytics.SearchConsole

  def configure(opts) do
    previous = Application.get_env(:brando, Analytics)
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])
    credentials = Jason.encode!(%{"client_email" => "stub@stub.iam.gserviceaccount.com", "private_key" => pem})

    Application.put_env(:brando, Analytics,
      plausible: [api_key: "stub", site_id: "stub.test", req_options: [plug: {Req.Test, Plausible}]],
      search_console: [
        credentials: credentials,
        property: "sc-domain:stub.test",
        req_options: [plug: {Req.Test, SearchConsole}]
      ]
    )

    Req.Test.set_req_test_to_shared(%{async: false})
    clear_cache()

    on_exit(fn ->
      Req.Test.set_req_test_to_private()
      clear_cache()

      if previous,
        do: Application.put_env(:brando, Analytics, previous),
        else: Application.delete_env(:brando, Analytics)
    end)

    pages = Keyword.get(opts, :pages, %{})
    queries = Keyword.get(opts, :queries, [])

    Req.Test.stub(Plausible, fn conn ->
      results =
        for {path, %{visitors: visitors} = page} <- pages,
            do: %{"metrics" => [visitors, page[:pageviews] || visitors], "dimensions" => [path]}

      Req.Test.json(conn, %{"results" => results})
    end)

    Req.Test.stub(SearchConsole, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      cond do
        conn.host == "oauth2.googleapis.com" ->
          Req.Test.json(conn, %{"access_token" => "stub-token", "expires_in" => 3600})

        Jason.decode!(body)["dimensions"] == ["query"] ->
          Req.Test.json(conn, %{"rows" => Enum.map(queries, &row(&1.query, &1))})

        true ->
          rows = for {path, %{impressions: _} = page} <- pages, do: row("https://stub.test" <> path, page)
          Req.Test.json(conn, %{"rows" => rows})
      end
    end)

    :ok
  end

  defp row(key, page) do
    %{
      "keys" => [key],
      "clicks" => page[:clicks] || 0,
      "impressions" => page[:impressions] || 0,
      "ctr" => page[:ctr] || 0.0,
      "position" => page[:position] || 0.0
    }
  end

  defp clear_cache do
    Brando.Cache.del({:seo_analytics, Analytics.period_days()})
    Brando.Cache.del({:seo_search_console_token, "stub@stub.iam.gserviceaccount.com"})
  end
end
