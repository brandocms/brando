defmodule Brando.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """

  use Brando.Web, :controller
  use Brando.Sequence, [
    :controller, [
      schema:  Brando.Image,
      filter: &Brando.Image.for_series_id/1
    ]
  ]

  import Brando.Gettext
  import Brando.Plug.HTML
  import Brando.Images.Utils, only: [recreate_sizes_for: 2]
  import Ecto.Query

  alias Brando.ImageSeries
  alias Brando.Images

  plug :put_section, "images"

  @doc false
  def new(conn, %{"id" => category_id}) do
    series    = %ImageSeries{image_category_id: String.to_integer(category_id)}
    changeset = ImageSeries.changeset(series, :create)

    render conn, :new, [
      page_title: gettext("New image series"),
      changeset:  changeset
    ]
  end

  @doc false
  def create(conn, %{"imageseries" => data}) do
    case Images.create_series(data, current_user(conn)) do
      {:ok, inserted_image_series} ->
        inserted_image_series = Brando.repo.preload(inserted_image_series, :image_category)
        category_slug = inserted_image_series.image_category.slug

        conn
        |> put_flash(:notice, gettext("Image series created"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index) <> "##{category_slug}")
      {:error, changeset} ->
        conn = put_flash(conn, :error, gettext("Errors in form"))

        render conn, :new, [
          page_title:   gettext("New image series"),
          image_series: data,
          changeset:    changeset
        ]
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    changeset =
      ImageSeries
      |> Brando.repo.get_by!(id: id)
      |> ImageSeries.changeset(:update)

    render conn, :edit, [
      page_title: gettext("Edit image series"),
      changeset:  changeset,
      id:         id
    ]
  end

  @doc false
  def update(conn, %{"imageseries" => data, "id" => id}) do
    case Images.update_series(id, data) do
      {:ok, inserted_series} ->
        category_slug = inserted_series.image_category.slug

        conn
        |> put_flash(:notice, gettext("Image series updated"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index) <> "##{category_slug}")
      {:error, changeset} ->
        conn
        |> put_flash(:error, gettext("Errors in form"))
        |> render(conn, :edit, [
            page_title:   gettext("Edit image series"),
            image_series: data,
            changeset:    changeset,
            id:           id
          ])
    end
  end

  @doc false
  def configure(conn, %{"id" => series_id}) do
    series = Brando.repo.get_by!(Brando.ImageSeries, id: series_id)

    series =
      if series.cfg do
        series
      else
        category = Brando.repo.get!(Brando.ImageCategory, series.image_category_id)
        Map.put(series, :cfg, category.cfg)
      end

    render conn, :configure, [
      page_title: gettext("Configure image series"),
      series:     series,
      id:         series_id
    ]
  end

  @doc false
  def configure_patch(conn, %{"config" => cfg, "sizes" => sizes, "id" => id}) do
    case Images.update_series_config(id, cfg, sizes) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Configuration updated"))
        |> redirect(to: helpers(conn).admin_image_series_path(conn, :configure, id))
      {:error, changeset} ->
        conn = put_flash(conn, :error, gettext("Errors in form"))

        render conn, :configure, [
          page_title: gettext("Configure image series"),
          config:     cfg,
          sizes:      sizes,
          changeset:  changeset,
          id:         id,
        ]
    end
  end

  @doc false
  def recreate_sizes(conn, %{"id" => id}) do
    user = current_user(conn)

    # send this off for async processing
    _ = Task.start_link(fn ->
      Brando.UserChannel.set_progress(user, 0)
      :ok = recreate_sizes_for(:image_series, id)
      Brando.UserChannel.set_progress(user, 1)
      Brando.UserChannel.alert(user, gettext("Recreated sizes for image series"))
    end)

    redirect(conn, to: helpers(conn).admin_image_path(conn, :index))
  end

  @doc false
  def upload(conn, %{"id" => id}) do
    series =
      ImageSeries
      |> preload([:image_category, :images])
      |> Brando.repo.get_by!(id: id)

    render conn, :upload, [
      page_title: gettext("Upload images"),
      series:     series
    ]
  end

  @doc false
  def upload_post(conn, %{"id" => id} = params) do
    series =
      ImageSeries
      |> preload([:image_category, :images])
      |> Brando.repo.get_by!(id: id)

    opts = Map.put(%{}, "image_series_id", series.id)
    cfg  = series.cfg || Brando.config(Brando.Images)[:default_config]

    case Images.check_for_uploads(params, current_user(conn), cfg, opts) do
      {:ok, image} ->
        render conn, :upload_post, image: image, status: 200, error_msg: nil
      {:error, error_msg} ->
        conn
        |> put_status(400)
        |> render(:upload_post, status: 400, error_msg: error_msg)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    record =
      ImageSeries
      |> preload([:image_category, :images, :creator])
      |> Brando.repo.get_by!(id: id)

    render conn, :delete_confirm, [
      page_title: gettext("Confirm deletion"),
      record:     record
    ]
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    {:ok, deleted_series} = Images.delete_series(id)
    category_slug = deleted_series.image_category.slug

    conn
    |> put_flash(:notice, gettext("Image series deleted"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index) <> "##{category_slug}")
  end
end
