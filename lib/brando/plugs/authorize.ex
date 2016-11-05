defmodule Brando.Plug.Authorize do
  @moduledoc """
  A plug for checking roles on user.
  """
  alias Brando.User
  import Plug.Conn
  import Phoenix.Controller, only: [render: 2, put_view: 2]

  @doc """
  Check `conn` for current_user's `role`.
  Halts on failure.
  """
  @spec authorize(Plug.Conn.t, atom) :: Plug.Conn.t
  def authorize(conn, role) do
    if current_user = Brando.Utils.current_user(conn) do
      User.role?(current_user, role) && conn || no_access(conn)
    else
      no_access(conn)
    end
  end

  @spec no_access(Plug.Conn.t) :: Plug.Conn.t
  defp no_access(conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(Brando.SessionView)
    |> render("no_access.html")
    |> halt
  end
end
