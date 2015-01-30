defmodule Brando.Plugs.Role do
  @moduledoc """
  A plug for checking roles on user.
  """
  import Plug.Conn
  alias Brando.Users.Model.User

  @doc """
  Check `conn` for current_user's `role`.
  Halts on failure.
  """
  def check_role(conn, role) do
    if current_user = get_session(conn, :current_user) do
      if User.has_role?(current_user, role), do: conn, else: conn |> no_access
    else
      conn |> no_access
    end
  end
  defp no_access(conn), do: conn |> send_resp(403, "Ingen adgang.") |> halt
end