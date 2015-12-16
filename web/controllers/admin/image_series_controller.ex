defmodule Brando.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """

  use Brando.Web, :controller
  use Brando.Sequence,
    [:controller, [model: Brando.Image, filter: &Brando.Image.for_series_id/1]]

  import Brando.Gettext
  import Brando.Plug.HTML
  import Brando.Utils, only: [helpers: 1]
  import Ecto.Query

  plug :put_section, "images"

  @doc false
  def new(conn, %{"id" => category_id}) do
    model = conn.private[:series_model]
    params = %{"image_category_id" => String.to_integer(category_id)}
    changeset = model.changeset(model.__struct__, :create, params)

    conn
    |> assign(:page_title, gettext("New image series"))
    |> assign(:changeset, changeset)
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imageseries" => image_series}) do
    model = conn.private[:series_model]

    case model.create(image_series, Brando.Utils.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Image series created"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("New image series"))
        |> assign(:image_series, image_series)
        |> assign(:changeset, changeset)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:series_model]
    changeset =
      model
      |> Brando.repo.get_by!(id: id)
      |> model.changeset(:update)

    conn
    |> assign(:page_title, gettext("Edit image series"))
    |> assign(:changeset, changeset)
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
        |> put_flash(:notice, gettext("Image series updated"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Edit image series"))
        |> assign(:image_series, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:edit)
    end
  end

  @doc false
  def configure(conn, %{"id" => series_id}) do
    model = conn.private[:series_model]
    data = Brando.repo.get_by!(model, id: series_id)
    {:ok, cfg} = Brando.Type.ImageConfig.dump(data.cfg)
    changeset =
      data
      |> Map.put(:cfg, cfg)
      |> model.changeset(:update)

    conn
    |> assign(:page_title, gettext("Configure image series"))
    |> assign(:changeset, changeset)
    |> assign(:id, series_id)
    |> render(:configure)
  end

  @doc false
  def configure_patch(conn, %{"imageseriesconfig" => form_data, "id" => id}) do
    model = conn.private[:series_model]
    record = Brando.repo.get_by!(model, id: id)

    case model.update(record, form_data) do
      {:ok, updated_record} ->
        # recreate image sizes
        Brando.ImageSeries.recreate_sizes(updated_record.id)

        conn
        |> put_flash(:notice, gettext("Image series configured"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Configure image series"))
        |> assign(:image_series, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
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
    |> assign(:page_title, gettext("Upload images"))
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
    cfg = series.cfg
          || Brando.config(Brando.Images)[:default_config]
    {:ok, image} =
      image_model.check_for_uploads(params, Brando.Utils.current_user(conn),
                                    cfg, opts)
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
    |> assign(:page_title, gettext("Confirm deletion"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    series_model = conn.private[:series_model]
    record = series_model |> Brando.repo.get_by!(id: id)
    series_model.delete(record)

    conn
    |> put_flash(:notice, gettext("Image series deleted"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index))
  end
end
