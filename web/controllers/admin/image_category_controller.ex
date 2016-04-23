defmodule Brando.Admin.ImageCategoryController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """

  use Brando.Web, :controller
  use Brando.Sequence,
    [:controller, [model: Brando.ImageSeries,
                   filter: &Brando.ImageSeries.get_by_category_id/1]]

  import Brando.Plug.HTML
  import Brando.Utils, only: [helpers: 1, current_user: 1]
  import Brando.Images.Utils, only: [fix_size_cfg_vals: 1]
  import Brando.Gettext
  import Ecto.Query

  plug :put_section, "images"
  plug :scrub_params, "imagecategory" when action in [:create, :update]

  @doc false
  def new(conn, _params) do
    model = conn.private[:category_model]
    changeset = model.changeset(model.__struct__, :create)

    conn
    |> assign(:page_title, gettext("New image category"))
    |> assign(:changeset, changeset)
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imagecategory" => imagecategory}) do
    model = conn.private[:category_model]

    case model.create(imagecategory, current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Image category created"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("New image category"))
        |> assign(:imagecategory, imagecategory)
        |> assign(:changeset, changeset)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:category_model]
    changeset =
      model
      |> Brando.repo.get!(id)
      |> model.changeset(:update)

    conn
    |> assign(:page_title, gettext("Edit image category"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"imagecategory" => form_data, "id" => id}) do
    model = conn.private[:category_model]
    record = Brando.repo.get_by!(model, id: id)

    case model.update(record, form_data) do
      {:ok, _updated_record} ->
        conn
        |> put_flash(:notice, gettext("Image category updated"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Edit image category"))
        |> assign(:image_category, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:edit)
    end
  end

  @doc false
  def configure(conn, %{"id" => category_id}) do
    category = Brando.repo.get_by!(Brando.ImageCategory, id: category_id)

    conn
    |> assign(:page_title, gettext("Configure image category"))
    |> assign(:category, category)
    |> assign(:id, category_id)
    |> render(:configure)
  end

  @doc false
  def configure_patch(conn, %{"config" => cfg, "sizes" => sizes, "id" => id}) do
    record = Brando.repo.get_by!(Brando.ImageCategory, id: id)

    sizes = fix_size_cfg_vals(sizes)

    new_cfg =
      record.cfg
      |> Map.put(:allowed_mimetypes, String.split(cfg["allowed_mimetypes"], ", "))
      |> Map.put(:default_size, cfg["default_size"])
      |> Map.put(:size_limit, String.to_integer(cfg["size_limit"]))
      |> Map.put(:upload_path, cfg["upload_path"])
      |> Map.put(:sizes, sizes)

    cs = Brando.ImageCategory.changeset(record, :update, %{cfg: new_cfg})

    case Brando.repo.update(cs) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Configuration updated"))
        |> redirect(to: helpers(conn).admin_image_category_path(conn, :configure, id))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Configure image category"))
        |> assign(:config, cfg)
        |> assign(:sizes, sizes)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:configure)
    end
  end

  @doc false
  def propagate_configuration(conn, %{"id" => id}) do
    category = Brando.repo.get(Brando.ImageCategory, id)

    series = Brando.repo.all(
      from is in Brando.ImageSeries,
        where: is.image_category_id == ^category.id
    )

    # send this off for async processing
    Task.start_link(fn ->
      for s <- series do
        new_path = Path.join([category.cfg.upload_path, s.slug])

        new_cfg =
          category.cfg
          |> Map.put(:upload_path, new_path)

        s
        |> Brando.ImageSeries.changeset(:update, %{cfg: new_cfg})
        |> Brando.repo.update

        Brando.Images.Utils.recreate_sizes_for(series_id: s.id)
      end

      orphaned_series = Brando.Images.Utils.get_orphaned_series(series, starts_with: category.cfg.upload_path)

      msg =
        if orphaned_series != [] do
          gettext("Category propagated, but you have orphaned series. Click <a href=\"%{url}\">here</a> to verify and delete",
                    url: Brando.helpers.admin_image_category_path(conn, :handle_orphans, id))
        else
          gettext("Category propagated")
        end

      Brando.SystemChannel.alert(msg)
    end)

    conn
    |> render(:propagate_configuration)
  end

  @doc false
  def handle_orphans(conn, %{"id" => id}) do
    category = Brando.repo.get(ImageCategory, id)
    orphaned_series = get_orphans(category)

    conn
    |> assign(:page_title, gettext("Handle orphaned image series"))
    |> assign(:orphaned_series, orphaned_series)
    |> assign(:category, category)
    |> render(:handle_orphans)
  end

  @doc false
  def handle_orphans_post(conn, %{"id" => id}) do
    category = Brando.repo.get(ImageCategory, id)
    orphaned_series = get_orphans(category)

    for s <- orphaned_series do
      File.rm_rf!(s)
    end

    conn
    |> put_flash(:notice, gettext("Orphans deleted"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index))
  end

  defp get_orphans(category) do
    series = Brando.repo.all(
      from is in ImageSeries,
        where: is.image_category_id == ^category.id
    )

    Brando.Images.Utils.get_orphaned_series(series, starts_with: category.cfg.upload_path)
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:category_model]
    record =
      model
      |> preload([:creator, :image_series])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, gettext("Confirm deletion"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:category_model]
    record = Brando.repo.get_by!(model, id: id)
    model.delete(record)

    conn
    |> put_flash(:notice, gettext("Image category deleted"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index))
  end
end
