defmodule Brando.Images.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """
  use Phoenix.Controller
  import Brando.Utils, only: [add_css: 2, add_js: 2]

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
  def edit(conn, %{"id" => id}) do
    model = conn.private[:series_model]
    data = model.get(id: id)
    conn
    |> assign(:image_series, data)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"imageseries" => form_data, "id" => id}) do
    model = conn.private[:series_model]
    record = model.get(id: String.to_integer(id))
    case model.update(record, form_data) do
      {:ok, updated_record} ->
        conn
        |> put_flash(:notice, "Serie oppdatert.")
        |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:image_series, form_data)
        |> assign(:errors, errors)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def upload(conn, %{"id" => id}) do
    model = conn.private[:series_model]
    series = model.get!(id: id)
    conn
    |> add_css("dropzone/dropzone.css")
    |> add_js("dropzone/dropzone.js")
    |> assign(:series, series)
    |> render(:upload)
  end

  @doc false
  def upload_post(conn, %{"id" => id} = params) do
    series_model = conn.private[:series_model]
    image_model = conn.private[:image_model]
    series = series_model.get!(id: id)
    opts = Map.put(%{}, "image_series_id", series.id)
    cfg = series.image_category.cfg || Brando.config(Brando.Images)[:default_config]
    {:ok, image} = image_model.check_for_uploads(params, Brando.HTML.current_user(conn), cfg, opts)
    conn
    |> render(:upload_post, image)
  end

  @doc false
  def sort(conn, %{"id" => id}) do
    series_model = conn.private[:series_model]
    series = series_model.get!(id: id)
    conn
    |> assign(:series, series)
    |> render(:sort)
  end

  @doc false
  def sort_post(conn, %{"id" => id, "order" => ids} = params) do
    vals = Range.new(0, length(ids))
    image_model = conn.private[:image_model]
    image_model.reorder_images(ids, vals)
    conn |> render(:sort_post)
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
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