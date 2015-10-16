defmodule Brando.Admin.PageController do
  @moduledoc """
  Controller for the Brando Pages module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries

  import Brando.Gettext
  import Brando.Plug.HTML
  import Brando.Utils, only: [helpers: 1]

  plug :put_section, "pages"
  plug :scrub_params, "page" when action in [:create, :update]

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    pages =
      model
      |> model.with_parents_and_children
      |> model.order
      |> Brando.repo.all

    conn
    |> assign(:page_title, gettext("Index - pages"))
    |> assign(:pages, pages)
    |> render(:index)
  end

  @doc false
  def rerender(conn, _params) do
    model = conn.private[:model]
    pages =
      model
      |> Brando.repo.all

    for page <- pages do
      model.rerender_html(model.changeset(page, :update, %{}))
    end

    conn
    |> put_flash(:notice, gettext("Pages re-rendered"))
    |> redirect(to: helpers(conn).admin_page_path(conn, :index))
  end

  @doc false
  def show(conn, %{"id" => id}) do
    model = conn.private[:model]
    page =
      model
      |> model.with_children
      |> Brando.repo.get_by(id: id)

    conn
    |> assign(:page_title, gettext("Show page"))
    |> assign(:page, page)
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    model = conn.private[:model]
    changeset = model.changeset(model.__struct__, :create)
    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, gettext("New page"))
    |> render(:new)
  end

  @doc false
  def create(conn, %{"page" => page}) do
    model = conn.private[:model]
    case model.create(page, Brando.Utils.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Page created"))
        |> redirect(to: helpers(conn).admin_page_path(conn, :index))
      {:error, changeset} ->
        conn
        |> put_flash(:error, gettext("Errors in form"))
        |> assign(:page_title, gettext("New page"))
        |> assign(:page, page)
        |> assign(:changeset, changeset)
        |> render(:new)
    end
  end

  @doc false
  def duplicate(conn, %{"id" => id}) do
    model = conn.private[:model]
    page =
      model
      |> Brando.repo.get_by(id: id)
      |> Map.drop([:__struct__, :__meta__, :id,
                   :key, :slug, :title,
                   :children, :creator, :parent,
                   :updated_at, :inserted_at])

    changeset = model.changeset(%Brando.Page{}, :create, page)

    conn
    |> put_flash(:notice, gettext("Page duplicated"))
    |> assign(:page_title, gettext("New page"))
    |> assign(:page, page)
    |> assign(:changeset, changeset)
    |> render(:new)
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:model]
    changeset =
      model
      |> Brando.repo.get!(id)
      |> model.encode_data
      |> model.changeset(:update)

      conn
      |> assign(:page_title, gettext("Edit page"))
      |> assign(:changeset, changeset)
      |> assign(:id, id)
      |> render(:edit)
  end

  @doc false
  def update(conn, %{"page" => form_data, "id" => id}) do
    model = conn.private[:model]
    page = Brando.repo.get_by!(model, id: id)
    case model.update(page, form_data) do
      {:ok, _updated_page} ->
        conn
        |> put_flash(:notice, gettext("Page updated"))
        |> redirect(to: helpers(conn).admin_page_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Edit page"))
        |> assign(:page, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:model]
    record =
      model
      |> model.with_children
      |> Brando.repo.get_by(id: id)

    conn
    |> assign(:page_title, gettext("Confirm deletion"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = Brando.repo.get_by!(model, id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, gettext("Page deleted"))
    |> redirect(to: helpers(conn).admin_page_path(conn, :index))
  end
end
