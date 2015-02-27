defmodule Brando.Images.Admin.ImageController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  use Phoenix.Controller

  plug :action

  @doc false
  def index(conn, _params) do
    # show images by tabbed category, then series.
    category_model = conn.private[:category_model]
    conn
    |> assign(:categories, category_model.all)
    |> render(:index)
  end
end