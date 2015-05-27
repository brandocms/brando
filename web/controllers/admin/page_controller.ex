defmodule Brando.Admin.PageController do
  @moduledoc """
  Controller for the Brando Pages module.
  """
  use Brando.Web, :controller
  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries

  import Brando.Plug.Section
  import Brando.HTML.Inspect, only: [model_name: 2]

  plug :put_section, "pages"
  plug :scrub_params, "page" when action in [:create, :update]
  plug :action

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    conn
    |> assign(:pages, model.all_parents_and_children)
    |> render(:index)
  end

  @doc false
  def show(conn, %{"id" => id}) do
    model = conn.private[:model]
    conn
    |> assign(:page, model.get_with_children!(id: id))
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    conn
    |> render(:new)
  end

  @doc false
  def create(conn, %{"page" => page}) do
    model = conn.private[:model]
    case model.create(page, Brando.HTML.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, "Side opprettet.")
        |> redirect(to: router_module(conn).__helpers__.admin_page_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:page, page)
        |> assign(:errors, errors)
        |> put_flash(:error, "Feil i skjema")
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:model]
    if page = model.get(id: id) do
      page = page
      |> model.encode_data
      conn
      |> assign(:page, page)
      |> assign(:id, id)
      |> render(:edit)
    else
      conn |> put_status(:not_found) |> render(:not_found)
    end
  end

  @doc false
  def update(conn, %{"page" => form_data, "id" => id}) do
    model = conn.private[:model]
    page = model.get(id: String.to_integer(id))
    case model.update(page, form_data) do
      {:ok, _updated_page} ->
        conn
        |> put_flash(:notice, "Side oppdatert.")
        |> redirect(to: router_module(conn).__helpers__.admin_page_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:page, form_data)
        |> assign(:errors, errors)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = model.get_with_children!(id: id)
    conn
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = model.get!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, "#{model_name(record, :singular)} #{model.__repr__(record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_page_path(conn, :index))
  end
end