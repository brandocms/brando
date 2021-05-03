defmodule BrandoWebController do
  @moduledoc """
  Main controller for Brando backend
  """
  use BrandoWeb, :controller

  @doc false
  def index(conn, _params) do
    render(conn, :index)
  end
end
