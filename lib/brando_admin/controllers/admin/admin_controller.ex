defmodule BrandoAdminController do
  @moduledoc """
  Main controller for Brando backend
  """
  use BrandoAdmin, :controller

  @doc false
  def index(conn, _params) do
    render(conn, :index)
  end
end
