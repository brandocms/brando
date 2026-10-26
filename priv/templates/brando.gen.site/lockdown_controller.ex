defmodule <%= web_module %>.CMS.LockdownController do
  @moduledoc """
  The page `Brando.Plug.Lockdown` sends visitors to while the site is locked
  (`config :brando, lockdown: true`). A visitor who enters the configured
  `lockdown_password` browses the site for the rest of the session.

  The route is outside the `:brando_site` pipeline, whose lockdown plug would
  redirect it to itself, so it resolves the site (`Brando.Plug.Tenant`) here.
  """
  use BrandoWeb, :controller

  alias Brando.Plug.Lockdown

  plug Brando.Plug.Tenant
  plug :put_view, html: <%= web_module %>.CMS.LockdownHTML
  plug :put_layout, false
  plug :put_root_layout, html: {<%= web_module %>.CMS.LockdownHTML, :root}

  def index(conn, _params), do: render_form(conn, false)

  def unlock(conn, %{"password" => password}) when is_binary(password) do
    if Lockdown.password?(conn, password) do
      conn
      |> configure_session(renew: true)
      |> put_session(:lockdown_authorized, true)
      |> redirect(to: "/")
    else
      conn
      |> put_status(:unauthorized)
      |> render_form(true)
    end
  end

  def unlock(conn, _params), do: redirect(conn, to: Brando.helpers().lockdown_path(conn, :index))

  defp render_form(conn, failed?) do
    render(conn, :index,
      action: Brando.helpers().lockdown_path(conn, :unlock),
      failed?: failed?,
      password?: Lockdown.password() != nil
    )
  end
end
