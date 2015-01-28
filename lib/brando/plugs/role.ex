defmodule Brando.Plugs.Role do
  import Plug.Conn
  alias Brando.Users.Model.User
  def check_role(conn, role) do
    if current_user = get_session(conn, :current_user) do
      if User.has_role?(current_user, role), do: conn, else: conn |> no_access
    else
      conn |> no_access
    end
  end
  defp no_access(conn), do: conn |> send_resp(403, "Ingen adgang.") |> halt
end