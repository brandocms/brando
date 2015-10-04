defmodule Brando.Plug.AdminHostname do
  @moduledoc """
  Basic plug for checking hostname.

  Redirects to / if `conn.host` isn't `localhost` or doesn't start with `admin`

  ## Example

      import Brando.Plug.AdminHostname

      pipeline :admin do
        plug :admin_hostname
      end
  """
  import Phoenix.Controller, only: [redirect: 2]

  @doc """
  Checks that `conn.host` has admin prefix.
  """
  def admin_hostname(conn, _) do
    cond do
      String.starts_with?(conn.host, "admin") ->
        conn
      conn.host == "localhost" ->
        conn
      true ->
        conn |> redirect(to: "/")
    end
  end
end