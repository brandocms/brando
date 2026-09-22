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

    html = render_async(view)
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
    html = render_async(view)
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
    html = render_async(view)
    assert html =~ "seo-audit"
    refute html =~ "seo_form"
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
      html = render_async(view)

      assert html =~ "Unassisted"
      refute has_element?(view, ".seo-context-picker")

      view |> element("button.seo-row-toggle", "Details") |> render_click()
      refute has_element?(view, "button[phx-click=generate_description]")
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
      render_async(view)

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
  end

  defp configure_ai do
    previous = Application.get_env(:brando, Brando.AI)

    Application.put_env(:brando, Brando.AI,
      enabled: true,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-key"]]
    )

    on_exit(fn ->
      if previous, do: Application.put_env(:brando, Brando.AI, previous), else: Application.delete_env(:brando, Brando.AI)
    end)
  end
end
