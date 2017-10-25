defmodule Brando.AuthHandler.GQLAuthHandler do
  @moduledoc """
  """
  use Brando.Web, :controller

  def unauthenticated(conn, _params) do
    conn
    |> put_status(406)
    |> json(%{error: "Unauthenticated"})
  end
end
