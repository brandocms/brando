defmodule Brando.Plug.SiteFrontend do
  @moduledoc """
  Applies the current site's frontend module (`Brando.Site.Frontend`) to a
  request: its `PageHTML` as the HTML view, its root layout with no inner
  layout, and its `layout_assigns/1`.

  Make it the page controller's last plug, after any `put_view`,
  `put_layout` or `put_root_layout` the controller has, so the site's choices
  replace them:

      defmodule MyAppWeb.CMS.PageController do
        use BrandoWeb, :controller

        plug :put_view, html: MyAppWeb.CMS.PageHTML
        plug :put_layout, false
        plug :put_root_layout, html: {MyAppWeb.CMS.Layouts, :root}
        plug Brando.Plug.SiteFrontend
      end

  It reads the site from `Brando.Plug.Tenant` and `conn.assigns.language`
  from the locale plug, so both run before it, in the router pipeline.

  A controller that renders its own templates in the site's layout passes
  `view: false`: the plug then sets the root layout and the layout assigns
  and leaves the view alone.

      plug Brando.Plug.SiteFrontend, view: false

  In `:multi`, once `site_frontends` has an entry, a site without one answers
  404. With nothing configured the conn passes through unchanged, and the
  controller's own view and layouts stand.
  """

  import Phoenix.Controller, only: [put_layout: 2, put_root_layout: 2, put_view: 2]
  import Plug.Conn, only: [halt: 1, merge_assigns: 2, send_resp: 3]

  alias Brando.Site.Frontend

  @behaviour Plug

  @impl Plug
  def init(opts), do: Keyword.validate!(opts, view: true)

  @impl Plug
  def call(conn, opts) do
    case Frontend.current() do
      :legacy ->
        conn

      nil ->
        conn
        |> send_resp(404, "Not found")
        |> halt()

      frontend ->
        conn
        |> maybe_put_view(frontend, Keyword.get(opts, :view, true))
        |> put_layout(false)
        |> put_root_layout(html: frontend.root_layout())
        |> merge_assigns(Map.to_list(frontend.layout_assigns(conn.assigns.language)))
    end
  end

  defp maybe_put_view(conn, frontend, true), do: put_view(conn, html: frontend.page_html())
  defp maybe_put_view(conn, _frontend, false), do: conn
end
