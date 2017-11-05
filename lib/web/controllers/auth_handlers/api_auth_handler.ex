defmodule Brando.AuthHandler.APIAuthHandler do
  @moduledoc """
  """
  use Brando.Web, :controller

  def unauthenticated(conn, _params) do
    conn
    |> put_status(401)
    |> json(%{error: "Unauthenticated, sorry!"})
  end
end
