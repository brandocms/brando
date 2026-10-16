defmodule <%= web_module %>.CMS.LockdownController do
  @moduledoc """
  The page `Brando.Plug.Lockdown` sends visitors to while the site is locked
  (`config :brando, lockdown: true`). A visitor who enters the configured
  `lockdown_password` browses the site for the rest of the session.
  """
  use BrandoWeb, :controller

  plug :put_view, html: <%= web_module %>.CMS.LockdownHTML
  plug :put_layout, false
  plug :put_root_layout, html: {<%= web_module %>.CMS.LockdownHTML, :root}

  def index(conn, _params), do: render_form(conn, false)

  def unlock(conn, %{"password" => password}) when is_binary(password) do
    if password?(password) do
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
      password?: password() != nil
    )
  end

  defp password?(given) do
    case password() do
      nil -> false
      password -> Plug.Crypto.secure_compare(given, password)
    end
  end

  defp password do
    case Brando.config(:lockdown_password) do
      password when is_binary(password) and password != "" -> password
      _ -> nil
    end
  end
end
