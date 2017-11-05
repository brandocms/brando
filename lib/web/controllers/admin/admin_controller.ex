defmodule Brando.AdminController do
  @moduledoc """
  Main controller for Brando backend
  """
  use Brando.Web, :controller

  @doc false
  def index(conn, _params) do
    conn
    |> put_layout({Brando.Admin.LayoutView, "admin.html"})
    |> render(:index)
  end
end
