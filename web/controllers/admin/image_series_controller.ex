defmodule Brando.Admin.ImageSeriesController do
  @moduledoc """
  Controller for the Brando ImageSeries module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  use Brando.Sequence, [:controller, [model: Brando.Image, filter: &Brando.Image.for_series_id/1]]

  import Brando.Plug.Section
  import Ecto.Query

  plug :put_section, "images"

  @doc false
  def new(conn, %{"id" => category_id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:series_model]
    changeset = model.changeset(Map.put(model.__struct__, :image_category_id, String.to_integer(category_id)), :create)
    conn
    |> assign(:page_title, t!(language, "title.new"))
    |> assign(:changeset, changeset)
    # |> assign(:image_series, image_series)
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imageseries" => image_series}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:series_model]
    case model.create(image_series, Brando.HTML.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, t!(language, "flash.created"))
        |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.new"))
        |> assign(:image_series, image_series)
        |> assign(:changeset, changeset)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:series_model]
    changeset =
      model
      |> Brando.repo.get_by!(id: id)
      |> model.changeset(:update)

    conn
    |> assign(:page_title, t!(language, "title.edit"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"imageseries" => form_data, "id" => id}) do
    language = Brando.I18n.get_language(conn)
    series_model = conn.private[:series_model]
    record = series_model |> Brando.repo.get_by!(id: id)
    case series_model.update(record, form_data) do
      {:ok, _updated_record} ->
        conn
        |> put_flash(:notice, t!(language, "flash.updated"))
        |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.edit"))
        |> assign(:image_series, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:edit)
    end
  end

  @doc false
  def upload(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    series_model = conn.private[:series_model]
    series =
      series_model
      |> preload([:image_category, :images])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, t!(language, "title.upload"))
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
    language = Brando.I18n.get_language(conn)
    series_model = conn.private[:series_model]
    record =
      series_model
      |> preload([:image_category, :images, :creator])
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, t!(language, "title.delete_confirm"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    series_model = conn.private[:series_model]
    record = series_model |> Brando.repo.get_by!(id: id)
    series_model.delete(record)
    conn
    |> put_flash(:notice, t!(language, "flash.deleted"))
    |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
  end

  locale "no", [
    title: [
      index: "Bildeserieoversikt",
      upload: "Last opp til bildeserie",
      new: "Ny bildeserie",
      edit: "Endre bildeserie",
      delete_confirm: "Bekreft sletting av bildeserie",
    ],
    flash: [
      form_error: "Feil i skjema",
      updated: "Bildeserie oppdatert",
      created: "Bildeserie opprettet",
      deleted: "Bildeserie slettet"
    ]
  ]

  locale "en", [
    title: [
      index: "Index – Image series",
      upload: "Upload to image serie",
      new: "New image serie",
      edit: "Edit image serie",
      delete_confirm: "Confirm image serie deletion",
    ],
    flash: [
      form_error: "Error(s) in form",
      updated: "Image serie updated",
      created: "Image serie created",
      deleted: "Image serie deleted"
    ]
  ]
end