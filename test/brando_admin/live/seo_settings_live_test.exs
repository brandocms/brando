defmodule BrandoAdmin.SEOSettingsLiveTest do
  # The SEO settings form and what the site serves from it: the search
  # preview, the fallback description in a page's meta tags, robots.txt and
  # redirects. This was most of e2e/playwright/tests/configuration/seo.spec.js.
  # Uploading the fallback image and the narrow layout stay in the browser.
  use Brando.LiveCase

  import Phoenix.Component, only: [sigil_H: 2]

  alias Brando.Pages.Page

  setup do
    # Saving refreshes the global SEO cache. Put back what it held, since the
    # rows behind the new value are rolled back.
    cached = Brando.Cache.get(:seo)
    on_exit(fn -> Brando.Cache.put(:seo, cached, :infinite) end)
    :ok
  end

  # A page's meta tags as the site's controllers set and render them.
  defp page_meta(page) do
    conn =
      Phoenix.ConnTest.build_conn(:get, "/")
      |> Plug.Conn.assign(:language, "en")
      |> Brando.Plug.HTML.put_meta(Page, page)

    assigns = %{conn: conn}

    ~H"""
    <Brando.HTML.render_meta conn={@conn} />
    """
    |> rendered_to_string()
    |> Floki.parse_fragment!()
    |> Floki.find("meta[name]")
    |> Enum.group_by(&hd(Floki.attribute(&1, "name")), &hd(Floki.attribute(&1, "content")))
  end

  test "SEO settings preview, save, and reach the site's meta tags, robots.txt and redirects", %{conn: conn} do
    index = Factory.insert(:page, title: "Index", uri: "index", meta_description: nil, status: :published)

    {:ok, view, _html} = live(conn, "/admin/config/seo")
    render_async(view)

    view
    |> form("#seo_form_form", %{
      "seo" => %{"fallback_meta_title" => "Brando CMS", "fallback_meta_description" => "Brando CMS: A CMS of sorts."}
    })
    |> render_change()

    assert view |> element(".seo-search-preview") |> render() =~ "Brando CMS: A CMS of sorts."
    assert view |> element(".seo-preview-title") |> render() =~ ~r/>\s*Brando CMS\s*</

    view |> element("#seo_form_form button", "Add entry") |> render_click()
    # A new redirect starts as an example rule: /example/:slug to /new/:slug.
    assert has_element?(view, "input[name='seo[redirects][0][from]'][value='/example/:slug']")

    view
    |> form("#seo_form_form", %{
      "seo" => %{
        "base_url" => "https://brando.dev",
        "robots" => "User-agent: *\nDisallow: /secret",
        "redirects" => %{"0" => %{"code" => "301"}}
      }
    })
    |> render_submit()

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    assert seo.fallback_meta_description == "Brando CMS: A CMS of sorts."
    assert seo.base_url == "https://brando.dev"

    # The front page has no description of its own, so it gets the fallback.
    # Loaded as a site's page controller loads it.
    {:ok, index} =
      Brando.Pages.get_page(%{
        matches: %{id: index.id},
        status: :published,
        preload: [:alternate_entries, :vars]
      })

    meta = page_meta(index)
    assert meta["description"] == ["Brando CMS: A CMS of sorts."]
    assert meta["title"] == ["Index"]

    robots = get(build_conn(), "/robots.txt")
    assert robots.resp_body =~ "User-agent: *\nDisallow: /secret"

    # An unknown path is answered by the fallback controller, which applies
    # the redirects.
    redirect =
      build_conn(:get, "/example/redirect")
      |> Plug.Conn.assign(:language, "en")
      |> BrandoWeb.FallbackController.call({:error, {:page, :not_found}})

    assert redirect.status == 301
    assert Plug.Conn.get_resp_header(redirect, "location") == ["/new/redirect"]
  end

  test "the AI crawler policy is saved with the form and written into robots.txt", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/config/seo")
    render_async(view)

    # Everything is allowed to start with, and nothing is written.
    assert has_element?(view, ~s(#seo-crawlers tr[data-crawler="GPTBot"] input[value="allow"][checked]))
    assert has_element?(view, ~s(#seo-crawlers tr[data-crawler="Bytespider"] input[value="allow"][checked]))
    refute has_element?(view, "#seo-crawlers .seo-crawler-lines pre")

    view
    |> form("#seo_form_form", %{
      "seo" => %{
        "robots" => "User-agent: *\nDisallow: /secret\n\nUser-agent: CCBot\nDisallow: /archive/",
        "crawler_policy" => %{"crawlers" => %{"GPTBot" => "block", "CCBot" => "block"}, "ai_train" => "no"}
      }
    })
    |> render_change()

    # The lines that will be written follow the choices before saving, and a
    # crawler the custom text names too says so.
    assert view |> element("#seo-crawlers .seo-crawler-lines pre") |> render() =~ "User-agent: GPTBot"
    assert has_element?(view, ~s(#seo-crawlers tr[data-crawler="CCBot"] .seo-crawler-purpose small))
    refute has_element?(view, ~s(#seo-crawlers tr[data-crawler="GPTBot"] .seo-crawler-purpose small))

    view |> form("#seo_form_form") |> render_submit()

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    assert seo.crawler_policy["crawlers"]["GPTBot"] == "block"
    assert seo.crawler_policy["ai_train"] == "no"

    robots = get(build_conn(), "/robots.txt")
    assert ["text/plain" <> _] = Plug.Conn.get_resp_header(robots, "content-type")

    assert String.starts_with?(
             robots.resp_body,
             "User-agent: *\nDisallow: /secret\n\nUser-agent: CCBot\nDisallow: /archive/"
           )

    assert robots.resp_body =~ "User-agent: GPTBot\nDisallow: /"
    assert robots.resp_body =~ "Content-Signal: search=yes, ai-input=yes, ai-train=no"

    {:ok, view, _html} = live(conn, "/admin/config/seo")
    assert has_element?(view, ~s(#seo-crawlers tr[data-crawler="GPTBot"] input[value="block"][checked]))
    assert has_element?(view, ~s(#seo-crawlers .seo-crawler-signal input[value="no"][checked]))
  end

  test "IndexNow is off until turned on, then shows its key file and last submission", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/config/seo")

    refute has_element?(view, "#seo-indexnow a[href$='.txt']")
    view |> element("[data-testid=indexnow-toggle]") |> render_click()

    %{key: key, enabled: true} = Brando.IndexNow.settings()
    assert has_element?(view, ~s(#seo-indexnow a[href$="/#{key}.txt"]))

    Req.Test.stub(Brando.IndexNow, &Plug.Conn.send_resp(&1, 202, ""))
    :ok = Brando.IndexNow.submit(["http://localhost/about"])

    {:ok, view, _html} = live(conn, "/admin/config/seo")
    assert view |> element("[data-testid=indexnow-response]") |> render() =~ "202 Accepted"

    view |> element("[data-testid=indexnow-toggle]") |> render_click()
    refute Brando.IndexNow.settings().enabled
  end

  # A redirect starts from a map of attributes (`default %{…}`). It is given
  # a key as it is added, like any new row, so a removal or a reorder that
  # names it works before the form is next validated.
  test "a new redirect has a key at once and can be removed by it straight away", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/config/seo")
    render_async(view)

    add = element(view, "#seo_form_form button", "Add entry")
    render_click(add)
    settle(view)

    [key] =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.attribute("input[name='seo[redirects][0][_key]']", "value")

    assert "new-" <> _ = key
    assert has_element?(view, "input[name='seo[redirects][0][from]'][value='/example/:slug']")

    [_, cid] = Regex.run(~r/&quot;target&quot;:(\d+)/, render(add))
    view |> with_target(String.to_integer(cid)) |> render_hook("remove_subentry", %{"key" => key})
    settle(view)

    refute has_element?(view, "input[name='seo[redirects][0][from]']")
  end
end
