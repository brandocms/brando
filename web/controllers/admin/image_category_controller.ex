defmodule Brando.Admin.ImageCategoryController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  use Brando.Sequence,
    [:controller, [model: Brando.ImageSeries,
                   filter: &Brando.ImageSeries.get_by_category_id/1]]
  import Brando.Plug.Section
  import Ecto.Query

  plug :put_section, "images"
  plug :scrub_params, "imagecategory" when action in [:create, :update]

  @doc false
  def new(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    changeset = model.changeset(model.__struct__, :create)
    conn
    |> assign(:page_title, t!(language, "title.new"))
    |> assign(:changeset, changeset)
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imagecategory" => imagecategory}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    case model.create(imagecategory, Brando.Utils.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, t!(language, "flash.created"))
        |> redirect(to: get_helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.new"))
        |> assign(:imagecategory, imagecategory)
        |> assign(:changeset, changeset)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    changeset =
      Brando.repo.get_by!(model, id: id)
      |> model.changeset(:update)

    conn
    |> assign(:page_title, t!(language, "title.edit"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"imagecategory" => form_data, "id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    record = Brando.repo.get_by!(model, id: id)
    case model.update(record, form_data) do
      {:ok, _updated_record} ->
        conn
        |> put_flash(:notice, t!(language, "flash.updated"))
        |> redirect(to: get_helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.edit"))
        |> assign(:image_category, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:edit)
    end
  end

  @doc false
  def configure(conn, %{"id" => category_id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    data = Brando.repo.get_by!(model, id: category_id)
    {:ok, cfg} = Brando.Type.ImageConfig.dump(data.cfg)
    changeset =
      Map.put(data, :cfg, cfg)
      |> model.changeset(:update)

    conn
    |> assign(:page_title, t!(language, "title.configure"))
    |> assign(:changeset, changeset)
    |> assign(:id, category_id)
    |> render(:configure)
  end

  @doc false
  def configure_patch(conn, %{"imagecategoryconfig" => form_data,
                              "id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    record = Brando.repo.get_by!(model, id: id)
    case model.update(record, form_data) do
      {:ok, _updated_record} ->
        conn
        |> put_flash(:notice, t!(language, "flash.configured"))
        |> redirect(to: get_helpers(conn).admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.configure"))
        |> assign(:image_category, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    record =
      model
      |> preload([:creator, :image_series])
      |> Brando.repo.get_by!(id: id)
    conn
    |> assign(:page_title, t!(language, "title.delete_confirm"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:category_model]
    record = model |> Brando.repo.get_by!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, t!(language, "flash.deleted"))
    |> redirect(to: get_helpers(conn).admin_image_path(conn, :index))
  end

  defp get_helpers(conn) do
    router_module(conn).__helpers__
  end

  locale "no", [
    title: [
      index: "Bildekategorioversikt",
      configure: "Konfigurér bildekategori",
      new: "Ny bildekategori",
      edit: "Endre bildekategori",
      delete_confirm: "Bekreft sletting av bildekategori",
    ],
    flash: [
      form_error: "Feil i skjema",
      updated: "Bildekategori oppdatert",
      created: "Bildekategori opprettet",
      deleted: "Bildekategori slettet",
      configured: "Bildekategori konfigurert"
    ]
  ]

  locale "en", [
    title: [
      index: "Index – Image cateogories",
      configure: "Configure image category",
      new: "New image category",
      edit: "Edit image category",
      delete_confirm: "Confirm image category deletion",
    ],
    flash: [
      form_error: "Error(s) in form",
      updated: "Image category updated",
      created: "Image category created",
      deleted: "Image category deleted",
      configured: "Image category konfigurert"
    ]
  ]
end
