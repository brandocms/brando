defmodule Brando.SEOController do
  @moduledoc """
  Controller for i18n actions.
  """
  use BrandoAdmin, :controller

  alias Brando.Cache
  alias Plug.Conn

  @default_robots """
  User-agent: *
  Disallow: /admin/
  """

  @doc false
  def robots(%{assigns: %{language: language}} = conn, _) do
    seo = Cache.SEO.get(language)

    case Map.get(seo, :robots) do
      nil ->
        conn
        |> Conn.resp(200, @default_robots)
        |> Conn.send_resp()

      robots ->
        conn
        |> Conn.resp(200, robots)
        |> Conn.send_resp()
    end
  end
end
