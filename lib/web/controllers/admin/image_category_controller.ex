defmodule Brando.Admin.ImageCategoryController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  use Brando.Web, :controller
  use Brando.Sequence, [
    :controller, [
      schema: Brando.ImageSeries,
      filter: &Brando.ImageSeries.by_category_id/1
    ]
  ]

  import Brando.Plug.HTML
  import Brando.Gettext
  import Ecto.Query

  alias Brando.ImageCategory
  alias Brando.Images

  plug :put_section, "images"
  plug :scrub_params, "imagecategory" when action in [:create, :update]

  @doc false
  def new(conn, _params) do
    changeset = ImageCategory.changeset(%ImageCategory{}, :create)

    conn
    |> assign(:page_title, gettext("New image category"))
    |> assign(:changeset, changeset)
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imagecategory" => data}) do
    user = current_user(conn)
    case Images.create_category(data, user) do
      {:ok, inserted_category} ->
        conn
        |> put_flash(:notice, gettext("Image category created"))
        |> redirect(to: helpers(conn).admin_image_path(conn, :index)
                        <> "##{inserted_category.slug}")
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("New image category"))
        |> assign(:imagecategory, data)
        |> assign(:changeset, changeset)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    changeset =
      ImageCategory
      |> Brando.repo.get!(id)
      |> ImageCategory.changeset(:update)

    conn
    |> assign(:page_title, gettext("Edit image category"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"imagecategory" => data, "id" => id}) do
    case Images.update_category(id, data) do
      {:ok, updated_category} ->
        redir = helpers(conn).admin_image_path(conn, :index) <> "##{updated_category.slug}"

        conn
        |> put_flash(:notice, gettext("Image category updated"))
        |> redirect(to: redir)
      {:propagate, updated_category} ->
        redir = helpers(conn).admin_image_category_path(conn, :propagate_configuration,
                                                        updated_category.id)

        conn
        |> put_flash(:notice, gettext("Image category updated"))
        |> redirect(to: redir)
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Edit image category"))
        |> assign(:image_category, data)
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
    case Images.update_category_config(id, cfg, sizes) do
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
    user     = current_user(conn)
    category = Images.get_category(id)
    series   = Images.get_series_for(category_id: category.id)

    # send this off for async processing
    _ = Task.start_link(fn ->
      Brando.UserChannel.set_progress(user, 0)

      series_count = Enum.count(series)
      progress_step = (series_count > 0) && div(100, series_count) / 100 || 0

      for s <- series do
        new_path = Path.join([category.cfg.upload_path, s.slug])
        new_cfg = Map.put(category.cfg, :upload_path, new_path)

        s
        |> Brando.ImageSeries.changeset(:update, %{cfg: new_cfg})
        |> Brando.repo.update

        :ok = Brando.Images.Utils.recreate_sizes_for(:image_series, s.id)
        Brando.UserChannel.increase_progress(user, progress_step)
      end

      orphaned_series = Images.get_all_orphaned_series()

      msg =
        if orphaned_series != [] do
          gettext("Category propagated, but you have orphaned series. " <>
                  "Click <a href=\"%{url}\">here</a> to verify and delete",
                  url: Brando.helpers.admin_image_category_path(conn, :handle_orphans))
        else
          gettext("Category propagated")
        end

      Brando.UserChannel.set_progress(user, 1.0)
      Brando.UserChannel.alert(user, msg)
    end)

    render(conn, :propagate_configuration)
  end

  @doc false
  def handle_orphans(conn, _params) do
    orphaned_series = Images.get_all_orphaned_series()

    conn
    |> assign(:page_title, gettext("Handle orphaned image series"))
    |> assign(:orphaned_series, orphaned_series)
    |> render(:handle_orphans)
  end

  @doc false
  def handle_orphans_post(conn, _params) do
    orphaned_series = Images.get_all_orphaned_series()

    for s <- orphaned_series, do:
      File.rm_rf!(s)

    conn
    |> put_flash(:notice, gettext("Orphans deleted"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index))
  end


  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    record =
      ImageCategory
      |> preload([:creator, :image_series])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, gettext("Confirm deletion"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    Images.delete_category(id)

    conn
    |> put_flash(:notice, gettext("Image category deleted"))
    |> redirect(to: helpers(conn).admin_image_path(conn, :index))
  end
end
