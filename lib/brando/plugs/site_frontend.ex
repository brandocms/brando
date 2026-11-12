defmodule Brando.Plug.SiteFrontend do
  @moduledoc """
  Applies the current site's frontend module (`Brando.Site.Frontend`) to a
  request: its `PageHTML` as the HTML view, its root layout, and its
  `layout_assigns/1`.

  Place it after `Brando.Plug.Tenant` and the locale plug, which give it the
  site and `conn.assigns.language`:

      pipeline :browser do
        # ...
        plug :put_locale
        # ...
        plug Brando.Plug.Tenant
        plug Brando.Plug.SiteFrontend
      end

  The view applies to every controller the pipeline leads to, and a
  controller's default view (`use Phoenix.Controller, formats: …`) does not
  replace one already set. A controller that renders its own templates in
  that pipeline sets them itself: `plug :put_view, html: MyAppWeb.ProjectHTML`.

  In `:multi`, once `site_frontends` has an entry, a site without one answers
  404. With nothing configured the conn passes through unchanged.
  """

  import Phoenix.Controller, only: [put_root_layout: 2, put_view: 2]
  import Plug.Conn, only: [halt: 1, merge_assigns: 2, send_resp: 3]

  alias Brando.Site.Frontend

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Frontend.current() do
      :legacy ->
        conn

      nil ->
        conn
        |> send_resp(404, "Not found")
        |> halt()

      frontend ->
        conn
        |> put_view(html: frontend.page_html())
        |> put_root_layout(html: frontend.root_layout())
        |> merge_assigns(Map.to_list(frontend.layout_assigns(conn.assigns.language)))
    end
  end
end
