defmodule Brando.Images.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """
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

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    require Logger
    Logger.debug(inspect(conn.private))
    model = conn.private[:series_model]
    record = model.get!(id: id)
    conn
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:series_model]
    record = model.get!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, "#{Brando.HTML.model_name(record, :singular)} #{model.__str__(record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
  end
end