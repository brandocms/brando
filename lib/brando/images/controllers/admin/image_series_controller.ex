defmodule Brando.Images.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  alias Brando.Images.Model.ImageSeries
  use Phoenix.Controller

  plug :action

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    conn
    |> assign(:series, model.all)
    |> render(:index)
  end
end