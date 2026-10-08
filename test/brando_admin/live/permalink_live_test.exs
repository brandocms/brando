defmodule BrandoAdmin.PermalinkLiveTest do
  # Changing a published page's URL offers a permanent redirect from the old
  # one. These were browser tests (e2e/playwright/tests/pages/permalink.spec.js);
  # the prompt, the save that follows and the SEO settings are server-rendered.
  # permalink_test.exs covers the handlers' redirect bookkeeping; this mounts
  # the real form. Escape and focus in the prompt stay in the spec.
  use Brando.LiveCase

  alias Brando.Pages.Page

  @form "#page_form_form"
  @prompt "#page_form-permalink-redirect"

  setup %{current_user: user} do
    # Redirects live in the SEO settings, cached for the whole node. Put back
    # what it held, since the rows behind the new value are rolled back.
    cached = Brando.Cache.get(:seo)
    on_exit(fn -> Brando.Cache.put(:seo, cached, :infinite) end)
    Brando.Cache.SEO.set()

    page =
      Factory.insert(:page,
        title: "About our studio",
        uri: "about-our-studio",
        status: :published,
        has_url: true,
        creator: user
      )

    %{page: page}
  end

  defp edit(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    view
  end

  # A form with blocks first asks the client for them, then saves.
  defp save(view, uri) do
    params = %{"page" => %{"uri" => uri}}
    view |> form(@form, params) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(@form, params) |> render_submit()
  end

  defp save_and_continue(view, uri) do
    view |> element("#save-dropdown button", "Save and continue editing") |> render_click()
    assert_push_event(view, "b:submit", %{}, 2_000)
    save(view, uri)
  end

  defp prompt(view) do
    assert has_element?(view, @prompt, "URL changed")
    html = view |> element(@prompt) |> render() |> Floki.parse_fragment!()
    [from] = html |> Floki.find("#page_form-permalink-from") |> Floki.attribute("value")
    [to] = html |> Floki.find("#page_form-permalink-to") |> Floki.attribute("value")
    {from, to}
  end

  defp dismiss(view), do: view |> element("#{@prompt} button", "Continue without redirect") |> render_click()
  defp create_redirect(view), do: view |> element("#{@prompt} button", "Create redirect") |> render_click()

  # What the site answers for an address no entry has: the fallback controller
  # applies the SEO redirects.
  defp visit(path) do
    build_conn(:get, path)
    |> Plug.Conn.assign(:language, "en")
    |> BrandoWeb.FallbackController.call({:error, {:page, :not_found}})
  end

  # No rule matches, so the fallback controller would answer 404 (the page
  # itself is served by its controller first).
  defp redirects?(path) do
    Brando.Sites.Redirects.test_redirect(String.split(path, "/", trim: true), "en") !=
      {:error, {:redirects, :no_match}}
  end

  defp seo_redirects(conn) do
    {:ok, view, _html} = live(conn, "/admin/config/seo")
    render_async(view)

    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("input[name^='seo[redirects]']")
    |> Enum.filter(&(&1 |> Floki.attribute("name") |> hd() |> String.ends_with?(["[from]", "[to]"])))
    |> Enum.map(&(&1 |> Floki.attribute("value") |> hd()))
  end

  test "a changed URL offers a redirect, which the site then serves and SEO lists", %{conn: conn, page: page} do
    view = edit(conn, page)
    save(view, "our-studio")

    assert prompt(view) == {"/en/about-our-studio", "/en/our-studio"}
    create_redirect(view)
    assert_redirect(view, "/admin/pages", 3_000)

    redirect = visit("/en/about-our-studio")
    assert redirect.status == 301
    assert Plug.Conn.get_resp_header(redirect, "location") == ["/en/our-studio"]

    assert seo_redirects(conn) == ["/en/about\\-our\\-studio$", "/en/our-studio"]
  end

  test "dismissing the prompt keeps editing, and the next change starts from the saved URL",
       %{conn: conn, page: page} do
    view = edit(conn, page)
    save_and_continue(view, "our-studio")
    assert prompt(view) == {"/en/about-our-studio", "/en/our-studio"}

    dismiss(view)
    refute has_element?(view, @prompt)
    # Still on the page's form, ready to save again
    assert Process.alive?(view.pid)
    refute has_element?(view, "#{@form} [data-testid=submit][disabled]")
    assert Repo.get!(Page, page.id).uri == "our-studio"

    save(view, "studio")
    assert {"/en/our-studio", _} = prompt(view)
    dismiss(view)
    assert_redirect(view, "/admin/pages", 3_000)
  end

  test "renaming back removes the redirect to it, even when the new one is declined", %{conn: conn, page: page} do
    view = edit(conn, page)
    save_and_continue(view, "our-studio")
    create_redirect(view)
    refute has_element?(view, @prompt)
    assert visit("/en/about-our-studio").status == 301

    save(view, "about-our-studio")
    assert prompt(view) == {"/en/our-studio", "/en/about-our-studio"}
    dismiss(view)
    assert_redirect(view, "/admin/pages", 3_000)

    # Neither address redirects any more, and SEO lists no rule
    refute redirects?("/en/about-our-studio")
    refute redirects?("/en/our-studio")
    assert seo_redirects(conn) == []
  end
end
