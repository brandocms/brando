defmodule Brando.Plug.Authenticate do
  @moduledoc """
  Basic plug for authenticating sessions.

  If :current_user is authenticated, assign :current_user to `conn`.
  If not, delete :current_user from session and redirect 302 to login page.

  ## Example

      plug Brando.Plug.Authenticate

  """
  @behaviour Plug

  alias Brando.User
  import Plug.Conn
  import Brando.Gettext
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  @spec init(Keyword.t) :: Keyword.t
  def init(options), do: options

  @spec call(Plug.Conn.t, Keyword.t) :: Plug.Conn.t
  def call(conn, _), do: allowed?(conn)

  @spec allowed?(Plug.Conn.t) :: Plug.Conn.t
  defp allowed?(%{private: %{plug_session: %{"current_user" => current_user}}} = conn) do
    if User.can_login?(current_user) do
      assign(conn, :current_user, current_user)
    else
      auth_failed(conn)
    end
  end

  defp allowed?(conn), do: auth_failed(conn)

  @spec auth_failed(Plug.Conn.t) :: Plug.Conn.t
  defp auth_failed(conn) do
    conn
    |> delete_session(:current_user)
    |> put_flash(:error, gettext("Access denied."))
    |> redirect(to: Brando.helpers.session_path(conn, :login))
    |> halt
  end
end
