defmodule Brando.Admin.PageController do
  @moduledoc """
  Controller for the Brando Pages module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries

  import Brando.Plug.Section
  import Brando.Utils, only: [helpers: 1]

  plug :put_section, "pages"
  plug :scrub_params, "page" when action in [:create, :update]

  @doc false
  def index(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    pages =
      model
      |> model.with_parents_and_children
      |> model.order
      |> Brando.repo.all

    conn
    |> assign(:page_title, t!(language, "title.index"))
    |> assign(:pages, pages)
    |> render(:index)
  end

  @doc false
  def rerender(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    pages =
      model
      |> Brando.repo.all

    for page <- pages do
      model.rerender_html(model.changeset(page, :update, %{}))
    end

    conn
    |> put_flash(:notice, t!(language, "flash.rerendered"))
    |> redirect(to: helpers(conn).admin_page_path(conn, :index))
  end

  @doc false
  def show(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    page =
      model
      |> model.with_children
      |> Brando.repo.get_by(id: id)

    conn
    |> assign(:page_title, t!(language, "title.show"))
    |> assign(:page, page)
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    changeset = model.changeset(model.__struct__, :create)
    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, t!(language, "title.new"))
    |> render(:new)
  end

  @doc false
  def create(conn, %{"page" => page}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    case model.create(page, Brando.Utils.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, t!(language, "flash.created"))
        |> redirect(to: helpers(conn).admin_page_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.new"))
        |> assign(:page, page)
        |> assign(:changeset, changeset)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:new)
    end
  end

  @doc false
  def duplicate(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    page = model |> Brando.repo.get_by(id: id)
    {:ok, duplicated_page} = model.duplicate(page)

    conn
    |> put_flash(:notice, t!(language, "flash.duplicated"))
    |> redirect(to: helpers(conn).admin_page_path(conn, :edit,
                                                  duplicated_page.id))
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    changeset =
      model
      |> Brando.repo.get!(id)
      |> model.encode_data
      |> model.changeset(:update)

      conn
      |> assign(:page_title, t!(language, "title.edit"))
      |> assign(:changeset, changeset)
      |> assign(:id, id)
      |> render(:edit)
  end

  @doc false
  def update(conn, %{"page" => form_data, "id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    page = Brando.repo.get_by!(model, id: id)
    case model.update(page, form_data) do
      {:ok, _updated_page} ->
        conn
        |> put_flash(:notice, t!(language, "flash.updated"))
        |> redirect(to: helpers(conn).admin_page_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.edit"))
        |> assign(:page, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    record =
      model
      |> model.with_children
      |> Brando.repo.get_by(id: id)

    conn
    |> assign(:page_title, t!(language, "title.delete_confirm"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    record = Brando.repo.get_by!(model, id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, t!(language, "flash.deleted"))
    |> redirect(to: helpers(conn).admin_page_path(conn, :index))
  end

  locale "no", [
    title: [
      index: "Sideoversikt",
      show: "Vis side",
      new: "Ny side",
      edit: "Endre side",
      delete_confirm: "Bekreft sletting av side",
    ],
    flash: [
      form_error: "Feil i skjema",
      updated: "Side oppdatert",
      created: "Side opprettet",
      duplicated: "Side duplisert",
      deleted: "Side slettet",
      rerendered: "Sider rendret på nytt"
    ]
  ]

  locale "en", [
    title: [
      index: "Index – Pages",
      show: "Show page",
      new: "New page",
      edit: "Edit page",
      delete_confirm: "Confirm page deletion",
    ],
    flash: [
      form_error: "Error(s) in form",
      updated: "Page updated",
      created: "Page created",
      duplicated: "Page duplicated",
      deleted: "Page deleted",
      rerendered: "Pages re-rendered"
    ]
  ]
end
