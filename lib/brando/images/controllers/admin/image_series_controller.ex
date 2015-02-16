defmodule Brando.Images.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """
  alias Brando.Images.Model.ImageSeries
  use Phoenix.Controller

  plug :action

  @doc false
  def index(conn, _params) do
    series_model = conn.private[:series_model]
    conn
    |> assign(:series, series_model.all)
    |> render(:index)
  end

  @doc false
  def new(conn, _params) do
    conn
    |> render(:new)
  end
end