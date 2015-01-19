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

  def call(conn, _opts), do: conn |> is_editor?

  defp is_editor?(conn) do
    if current_user = get_session(conn, :current_user) do
      assign(conn, :current_user, current_user)
      case current_user.editor do
        true -> conn
        false -> auth_failed(conn)
      end
    else
      auth_failed(conn)
    end
  end

  defp auth_failed(conn) do
    helpers = Brando.get_helpers
    conn
    |> delete_session(:current_user)
    |> put_resp_header("Location", helpers.auth_path(:login))
    |> resp(302, "")
    |> put_flash(:error, "Ingen tilgang.")
    |> send_resp
    |> halt
  end
end