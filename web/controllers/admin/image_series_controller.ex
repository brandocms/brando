defmodule Brando.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """

  use Brando.Web, :controller
  use Brando.Sequence,
    [:controller, [model: Brando.Image, filter: &Brando.Image.for_series_id/1]]

  import Brando.Gettext
  import Brando.Plug.HTML
  import Brando.Images.Utils, only: [recreate_sizes_for: 2, fix_size_cfg_vals: 1]
  import Brando.Utils, only: [helpers: 1]
  import Brando.Utils.Model, only: [put_creator: 2]
  import Ecto.Query

  alias Brando.Image
  alias Brando.ImageSeries

  plug :put_section, "images"

  @doc false
  def new(conn, %{"id" => category_id}) do
    series = %ImageSeries{image_category_id: String.to_integer(category_id)}
    changeset = ImageSeries.changeset(series, :create)

    conn
    |> assign(:page_title, gettext("New image series"))
    |> assign(:changeset, changeset)
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imageseries" => image_series}) do
    changeset =
      %ImageSeries{}
      |> put_creator(Brando.Utils.current_user(conn))
      |> ImageSeries.changeset(:create, image_series)

    case Brando.repo.insert(changeset) do
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
    changeset =
      ImageSeries
      |> Brando.repo.get_by!(id: id)
      |> ImageSeries.changeset(:update)

    conn
    |> assign(:page_title, gettext("Edit image series"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"imageseries" => image_series, "id" => id}) do
    changeset =
      ImageSeries
      |> Brando.repo.get_by!(id: id)
      |> ImageSeries.changeset(:update, image_series)

    case Brando.repo.update(changeset) do
      {:ok, _} ->
        # We have to check this here, since the changes have not been stored in
        # the ImageSeries.validate_paths() when we check.
        if Ecto.Changeset.get_change(changeset, :slug) do
          Brando.Images.Utils.recreate_sizes_for(:image_series, changeset.data.id)
        end

        conn
        |> put_flash(:notice, gettext("Image series updated"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Edit image series"))
        |> assign(:image_series, image_series)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:edit)
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

    conn
    |> assign(:page_title, gettext("Configure image series"))
    |> assign(:series, series)
    |> assign(:id, series_id)
    |> render(:configure)
  end

  @doc false
  def configure_patch(conn, %{"config" => cfg, "sizes" => sizes, "id" => id}) do
    record = Brando.repo.get_by!(Brando.ImageSeries, id: id)
    sizes = fix_size_cfg_vals(sizes)

    new_cfg =
      Map.get(record, :cfg) || %Brando.Type.ImageConfig{}
      |> Map.put(:allowed_mimetypes, String.split(cfg["allowed_mimetypes"], ", "))
      |> Map.put(:default_size, cfg["default_size"])
      |> Map.put(:size_limit, String.to_integer(cfg["size_limit"]))
      |> Map.put(:upload_path, cfg["upload_path"])
      |> Map.put(:sizes, sizes)

    cs = Brando.ImageSeries.changeset(record, :update, %{cfg: new_cfg})

    case Brando.repo.update(cs) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Configuration updated"))
        |> redirect(to: helpers(conn).admin_image_series_path(conn, :configure, id))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Configure image series"))
        |> assign(:config, cfg)
        |> assign(:sizes, sizes)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:configure)
    end
  end

  @doc false
  def recreate_sizes(conn, %{"id" => id}) do
    Brando.Images.Utils.recreate_sizes_for(:image_series, id)

    conn
    |> put_flash(:notice, gettext("Recreated sizes for image series"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index))
  end

  @doc false
  def upload(conn, %{"id" => id}) do
    series =
      ImageSeries
      |> preload([:image_category, :images])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, gettext("Upload images"))
    |> assign(:series, series)
    |> render(:upload)
  end

  @doc false
  def upload_post(conn, %{"id" => id} = params) do
    series =
      ImageSeries
      |> preload([:image_category, :images])
      |> Brando.repo.get_by!(id: id)

    opts = Map.put(%{}, "image_series_id", series.id)
    cfg = series.cfg || Brando.config(Brando.Images)[:default_config]
    {:ok, image} = Image.check_for_uploads(params, Brando.Utils.current_user(conn), cfg, opts)

    render(conn, :upload_post, image: image)
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    record =
      ImageSeries
      |> preload([:image_category, :images, :creator])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, gettext("Confirm deletion"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    series = Brando.repo.get_by!(ImageSeries, id: id)
    Brando.Images.Utils.delete_images_for(:image_series, series.id)
    Brando.repo.delete!(series)

    conn
    |> put_flash(:notice, gettext("Image series deleted"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index))
  end
end
