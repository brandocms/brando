defmodule Brando.Images.Admin.ImageCategoryController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  alias Brando.Images.Model.ImageCategory
  use Phoenix.Controller

  plug :action

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    conn
    |> assign(:categories, model.all)
    |> render(:index)
  end
end