defmodule Brando.Plug.Authorize do
  @moduledoc """
  A plug for checking roles on user.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [render: 2, put_view: 2]
  alias Brando.User

  @doc """
  Check `conn` for current_user's `role`.
  Halts on failure.
  """
  def authorize(%{private: %{plug_session: %{"current_user" => current_user}}} = conn, role) do
    User.has_role?(current_user, role) && conn || conn |> no_access
  end
  def authorize(conn, _) do
    conn |> no_access
  end
  defp no_access(conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(Brando.SessionView)
    |> render("no_access.html")
    |> halt
  end
end
