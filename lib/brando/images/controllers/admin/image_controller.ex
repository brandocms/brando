defmodule Brando.Images.Admin.ImageController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  use Phoenix.Controller
  import Brando.Plug.Section

  plug :put_section, "images"
  plug :action

  @doc false
  def index(conn, _params) do
    # show images by tabbed category, then series.
    category_model = conn.private[:category_model]
    conn
    |> assign(:categories, category_model.all)
    |> render(:index)
  end

  @doc false
  def delete_selected(conn, %{"ids" => ids}) do
    model = conn.private[:image_model]
    model.delete(ids)
    conn |> render(:delete_selected, ids: ids)
  end
end