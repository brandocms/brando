defmodule BrandoAdmin.Sites.SEOLiveTest do
  use Brando.LiveCase

  alias Brando.Factory
  alias Brando.Pages

  test "the settings tab renders the form and the content tab audits on demand", %{conn: conn} do
    user = Factory.insert(:random_user)

    {:ok, _} =
      Pages.create_page(
        %{title: "Audited page", uri: "audited", language: "en", template: "default.html", status: :published},
        user
      )

    {:ok, view, html} = live(conn, "/admin/config/seo")
    assert html =~ "seo_form"
    assert has_element?(view, "nav.seo-tabs button[aria-current=page]", "Settings")

    view |> element("nav.seo-tabs button", "Content SEO") |> render_click()
    assert_patch(view, "/admin/config/seo?tab=content")

    html = render_async(view, 5_000)
    assert html =~ "Audited page"
    assert has_element?(view, ".seo-audit-table")
    assert has_element?(view, ".seo-stats")

    view |> element("button.seo-row-toggle", "Details") |> render_click()
    assert has_element?(view, ".seo-audit-details .seo-check-table tr[data-status=fail]")
  end

  test "a recorded 404 matching an entry's slug can become a redirect", %{conn: conn} do
    user = Factory.insert(:random_user)
    Brando.Cache.SEO.set()

    {:ok, page} =
      Pages.create_page(
        %{title: "Moved page", uri: "moved-page", language: "en", template: "default.html", status: :published},
        user
      )

    Brando.Sites.FourOhFour.add_404(%Plug.Conn{path_info: ["blog", "moved-page"]})

    {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
    html = render_async(view, 5_000)
    assert html =~ "/blog/moved-page"

    view |> element(~s(.seo-redirects button[phx-value-from="/blog/moved-page"])) |> render_click()

    redirects = Brando.Cache.SEO.get("en").redirects

    assert Enum.any?(
             redirects,
             &(&1.from == "/blog/moved-page" and &1.to == Brando.Pages.Page.__absolute_url__(page) and &1.code == 301)
           )

    refute render(view) =~ ~s(phx-value-from="/blog/moved-page")
    refute Enum.any?(Brando.Sites.FourOhFour.list(), &(&1.url == "/blog/moved-page"))
  end

  test "opening the content tab directly runs the audit", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
    html = render_async(view, 5_000)
    assert html =~ "seo-audit"
    refute html =~ "seo_form"
  end

  describe "traffic" do
    test "figures, sorting and a page's searches, when the sources are configured", %{conn: conn} do
      user = Factory.insert(:random_user)

      {:ok, busy} =
        Pages.create_page(
          %{title: "Busy page", uri: "busy-page", language: "en", template: "default.html", status: :published},
          user
        )

      {:ok, _quiet} =
        Pages.create_page(
          %{title: "Quiet page", uri: "quiet-page", language: "en", template: "default.html", status: :published},
          user
        )

      path = Brando.SEO.Analytics.path(Pages.Page.__absolute_url__(busy))
      Brando.Cache.del({:seo_analytics_queries, 28, "https://stub.test" <> path})

      Brando.AnalyticsStub.configure(
        pages: %{path => %{visitors: 1200, clicks: 2, impressions: 900, ctr: 0.0022, position: 5.0}},
        queries: [%{query: "busy things", clicks: 2, impressions: 700, ctr: 0.003, position: 4.2}]
      )

      {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
      render_async(view, 5_000)

      assert has_element?(view, ".seo-sources", "Plausible (stub.test)")
      assert has_element?(view, ".seo-sources", "Google Search Console (sc-domain:stub.test)")
      assert has_element?(view, ".seo-audit-table th", "Visitors")
      assert has_element?(view, ".seo-stats", "Low click-through")

      view |> element(".seo-sort button[phx-value-sort=visitors]") |> render_click()
      assert has_element?(view, ".seo-sort button[phx-value-sort=visitors][aria-pressed=true]")
      # Most visited first.
      assert view |> element(".seo-audit-table tbody tr.seo-audit-row:first-child") |> render() =~ "Busy page"

      view |> element(".seo-audit-table tbody tr.seo-audit-row:first-child button.seo-row-toggle") |> render_click()
      render_async(view, 5_000)

      assert has_element?(view, ".seo-traffic dd", "1200")
      assert has_element?(view, ".seo-queries td", "busy things")
      assert has_element?(view, ".seo-check-table tr[data-status=warn]", "Search click-through")
    end

    test "nothing about traffic shows when no source is configured", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
      render_async(view, 5_000)

      refute has_element?(view, ".seo-sources")
      refute has_element?(view, ".seo-audit-table th", "Visitors")
    end
  end

  describe "AI actions" do
    test "a site without an AI provider gets the audit and none of the actions", %{conn: conn} do
      user = Factory.insert(:random_user)

      {:ok, _} =
        Pages.create_page(
          %{title: "Unassisted", uri: "unassisted", language: "en", template: "default.html", status: :published},
          user
        )

      {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
      html = render_async(view, 5_000)

      assert html =~ "Unassisted"
      refute has_element?(view, ".seo-context-picker")

      view |> element("button.seo-row-toggle", "Details") |> render_click()
      refute has_element?(view, "button[phx-click=generate_description]")
      refute has_element?(view, "button[phx-click=critique]")
      refute has_element?(view, ".seo-batch")
    end

    test "a configured site can pick what the prompt reads, and store it", %{conn: conn} do
      configure_ai()
      user = Factory.insert(:random_user)

      {:ok, _} =
        Pages.create_page(
          %{title: "Assisted", uri: "assisted", language: "en", template: "default.html", status: :published},
          user
        )

      {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
      render_async(view, 5_000)

      assert has_element?(view, ".seo-context-picker")
      view |> element(".seo-context-summary") |> render_click()
      # What Brando.Pages.Page declares through `trait :meta, ai: [...]`.
      assert has_element?(view, ".seo-context-picker .seo-chip[aria-pressed=true]", "blocks")

      view
      |> element(".seo-context-picker .seo-chip[phx-value-field=blocks]")
      |> render_click()

      refute has_element?(view, ".seo-context-picker .seo-chip[aria-pressed=true]", "blocks")
      assert Brando.SEO.Generate.stored_context_fields(Brando.Pages.Page, "en") == [:title, :language]
      # Picking a field must not collapse the panel it was picked in.
      assert has_element?(view, ".seo-context-summary[aria-expanded=true]")

      view |> element("button.seo-row-toggle", "Details") |> render_click()
      assert has_element?(view, "button[phx-click=generate_description]", "Write description")
    end

    test "missing descriptions are written in bulk and saved only once accepted", %{conn: conn} do
      configure_ai()
      Brando.AIStub.reply(fn prompt -> if prompt =~ "Bulk first", do: "About the first", else: "About the second" end)
      user = Factory.insert(:random_user)

      pages =
        for {title, uri} <- [{"Bulk first", "bulk-first"}, {"Bulk second", "bulk-second"}] do
          {:ok, page} =
            Pages.create_page(
              %{title: title, uri: uri, language: "en", template: "default.html", status: :published},
              user
            )

          page
        end

      {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
      render_async(view, 5_000)

      assert has_element?(view, ".seo-batch")
      view |> element(".seo-batch button[phx-click=confirm_batch]") |> render_click()
      view |> element(".seo-batch button[phx-click=start_batch]") |> render_click()

      # Oban runs inline in tests, so the suggestions are written by now.
      render_async(view, 5_000)
      assert has_element?(view, ".ai-suggestion[data-status=pending]", "Bulk first")
      assert has_element?(view, ".ai-suggestion textarea", "About the second")
      # Nothing is waiting any more, so there is nothing left to offer.
      refute has_element?(view, ".seo-batch")
      assert Enum.all?(pages, &(description(&1) == nil))

      [first, second] = Brando.SEO.Suggestions.list_open("en")

      view
      |> form("#suggestion-#{first.id} form", %{"text" => "Edited before saving"})
      |> render_submit()

      render_async(view, 5_000)
      assert description(Enum.find(pages, &(&1.id == first.entry_id))) == "Edited before saving"
      refute has_element?(view, "#suggestion-#{first.id}")

      view |> element(".ai-suggestions button[phx-click=accept_all_suggestions]") |> render_click()
      render_async(view, 5_000)

      assert description(Enum.find(pages, &(&1.id == second.entry_id))) == "About the second"
      refute has_element?(view, ".ai-suggestions")
    end

    test "an entry's meta can be reviewed by AI, advisory only", %{conn: conn} do
      configure_ai()
      Brando.AIStub.reply("- The description is generic.\n- It repeats the title.\n- Name the city.\n- A fourth point")
      user = Factory.insert(:random_user)

      {:ok, page} =
        Pages.create_page(
          %{
            title: "Reviewed",
            uri: "reviewed",
            language: "en",
            template: "default.html",
            status: :published,
            meta_description: "Reviewed page with a description"
          },
          user
        )

      {:ok, view, _html} = live(conn, "/admin/config/seo?tab=content")
      render_async(view, 5_000)

      view |> element("button.seo-row-toggle", "Details") |> render_click()
      view |> element("button[phx-click=critique]") |> render_click()
      render_async(view, 5_000)

      assert has_element?(view, ".seo-critique li", "The description is generic.")
      assert has_element?(view, ".seo-critique li", "Name the city.")
      refute has_element?(view, ".seo-critique li", "A fourth point")
      assert description(page) == "Reviewed page with a description"
    end
  end

  defp description(page) do
    {:ok, page} = Pages.get_page(%{matches: %{id: page.id}})
    page.meta_description
  end

  defp configure_ai, do: Brando.AIStub.configure(shared: true)
end
