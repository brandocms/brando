defmodule Brando.Plugs.Authenticate do
  @moduledoc """
  Basic plug for authenticating sessions. If :current_user is
  authenticated, assign :current_user to `conn`. If not, delete
  :current_user from session and redirect 302 to login page.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3]

  @behaviour Plug

  def init(options), do: options

  def call(conn, opts) do
    login_url = Dict.fetch!(opts, :login_url)
    conn |> is_editor?(login_url)
  end

  defp is_editor?(conn, login_url) do
    if current_user = get_session(conn, :current_user) do
      assign(conn, :current_user, current_user)
      case current_user.editor do
        true -> conn
        false -> auth_failed(conn, login_url)
      end
    else
      auth_failed(conn, login_url)
    end
  end

  defp auth_failed(conn, login_url) do
    conn
    |> delete_session(:current_user)
    |> put_resp_header("Location", login_url)
    |> resp(302, "")
    |> put_flash(:error, "Ingen tilgang.")
    |> send_resp
    |> halt
  end
end