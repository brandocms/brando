defmodule Brando.Images.Admin.ImageCategoryController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  alias Brando.Images.Model.ImageCategory
  use Phoenix.Controller

  plug :action

  @doc false
  def index(conn, _params) do
    category_model = conn.private[:category_model]
    conn
    |> assign(:categories, category_model.all)
    |> render(:index)
  end

  @doc false
  def new(conn, _params) do
    conn
    |> render(:new)
  end
end