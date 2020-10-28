defmodule Brando.SEOController do
  @moduledoc """
  Controller for i18n actions.
  """
  use Brando.Web, :controller
  alias Brando.Cache

  @default_robots """
  User-agent: *
  Disallow: /admin/
  """

  @doc false
  def robots(conn, _) do
    seo = Cache.SEO.get()

    case Map.get(seo, :robots) do
      nil ->
        conn
        |> Plug.Conn.resp(200, @default_robots)
        |> Plug.Conn.send_resp()

      robots ->
        conn
        |> Plug.Conn.resp(200, robots)
        |> Plug.Conn.send_resp()
    end
  end
end
