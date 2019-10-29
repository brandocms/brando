defmodule Brando.Guardian.GQLErrorHandler do
  @moduledoc """
  Guardian error handler
  """
  use Brando.Web, :controller

  def auth_error(conn, {:unauthenticated, _reason}, _opts) do
    conn
    |> put_status(406)
    |> json(%{error: "Unauthenticated"})
  end

  def auth_error(conn, {:invalid_token, _reason}, _opts) do
    conn
    |> put_status(406)
    |> json(%{error: "Invalid token"})
  end

  def auth_error(conn, {:no_resource_found, _reason}, _opts) do
    conn
    |> put_status(406)
    |> json(%{error: "Unknown resource type"})
  end
end
