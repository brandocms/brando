defmodule Brando.Plugs.LoginRequired do
  import Plug.Conn

  @behaviour Plug

  def init(options) do
    options
  end

  def call(conn, opts) do
    conn
    |> is_editor?(opts)
  end

  defp is_editor?(conn, opts) do
    if current_user = get_session(conn, :current_user) do
      assign(conn, :current_user, current_user)
      case current_user.editor do
        true -> conn
        false -> auth_failed(conn, opts)
      end
    else
      auth_failed(conn, opts)
    end
  end

  defp auth_failed(conn, opts) do
    helpers = Dict.fetch! opts, :helpers
    conn
    |> Plug.Conn.delete_session(:current_user)
    |> put_resp_header("Location", helpers.auth_path(:login))
    |> resp(302, "")
    |> Phoenix.Controller.put_flash(:error, "Ingen tilgang.")
    |> send_resp
    |> halt
  end
end