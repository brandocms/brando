defmodule Brando.Plug.Authorize do
  @moduledoc """
  A plug for checking roles on user.
  """
  import Plug.Conn
  alias Brando.User

  @doc """
  Check `conn` for current_user's `role`.
  Halts on failure.
  """
  def authorize(%{private: %{plug_session: %{"current_user" => current_user}}} = conn, role) do
    if User.has_role?(current_user, role), do: conn, else: conn |> no_access
  end
  def authorize(conn, _) do
    conn |> no_access
  end
  defp no_access(conn), do: conn |> send_resp(403, "Ingen adgang.") |> halt
end