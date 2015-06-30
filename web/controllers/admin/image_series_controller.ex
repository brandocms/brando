defmodule Brando.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """
  use Brando.Web, :controller
  use Brando.Sequence, [:controller, [model: Brando.Image, filter: &Brando.Image.get_by_series_id/1]]

  import Brando.Plug.Section
  import Brando.HTML.Inspect, only: [model_name: 2]
  import Ecto.Query

  plug :put_section, "images"

  @doc false
  def new(conn, %{"id" => category_id}) do
    image_series = %{"image_category_id" => String.to_integer(category_id)}
    conn
    |> assign(:image_series, image_series)
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imageseries" => image_series}) do
    model = conn.private[:series_model]
    case model.create(image_series, Brando.HTML.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, "Bildeserie opprettet.")
        |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:image_series, image_series)
        |> assign(:errors, errors)
        |> put_flash(:error, "Feil i skjema")
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:series_model]
    data = model |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:image_series, data)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"imageseries" => form_data, "id" => id}) do
    series_model = conn.private[:series_model]
    record = series_model |> Brando.repo.get_by!(id: id)
    case series_model.update(record, form_data) do
      {:ok, _updated_record} ->
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
    series_model = conn.private[:series_model]
    series =
      series_model
      |> preload([:image_category, :images])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:series, series)
    |> render(:upload)
  end

  @doc false
  def upload_post(conn, %{"id" => id} = params) do
    series_model = conn.private[:series_model]
    image_model = conn.private[:image_model]
    series =
      series_model
      |> preload([:image_category, :images])
      |> Brando.repo.get_by!(id: id)
    opts = Map.put(%{}, "image_series_id", series.id)
    cfg = series.image_category.cfg || Brando.config(Brando.Images)[:default_config]
    {:ok, image} = image_model.check_for_uploads(params, Brando.HTML.current_user(conn), cfg, opts)
    conn
    |> render(:upload_post, image: image)
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    series_model = conn.private[:series_model]
    record =
      series_model
      |> preload([:image_category, :images, :creator])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    series_model = conn.private[:series_model]
    record = series_model |> Brando.repo.get_by!(id: id)
    series_model.delete(record)
    conn
    |> put_flash(:notice, "#{model_name(record, :singular)} #{series_model.__repr__(record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
  end
end