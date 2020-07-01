defmodule Brando.AdminController do
  @moduledoc """
  Main controller for Brando backend
  """
  use Brando.Web, :controller

  @doc false
  def index(conn, _params) do
    render(conn, :index)
  end
end
