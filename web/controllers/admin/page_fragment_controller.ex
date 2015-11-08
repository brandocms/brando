defmodule Brando.Admin.PageFragmentController do
  @moduledoc """
  Controller for the Brando PageFragment module.
  """
  use Brando.Web, :controller
  use Brando.Villain, [:controller, [
    image_model: Brando.Image,
    series_model: Brando.ImageSeries]]

  import Brando.Gettext
  import Brando.Plug.HTML
  import Brando.Utils, only: [helpers: 1]
  import Ecto.Query

  plug :put_section, "page_fragments"
  plug :scrub_params, "page_fragment" when action in [:create, :update]

  @doc false
  def index(conn, _params) do
    model = conn.private[:fragment_model]
    conn
    |> assign(:page_fragments, model.all)
    |> assign(:page_title, gettext("Index - page fragments"))
    |> render(:index)
  end

  @doc false
  def show(conn, %{"id" => id}) do
    model = conn.private[:fragment_model]
    page =
      model
      |> preload(:creator)
      |> Brando.repo.get_by!(id: id)
    conn
    |> assign(:page_fragment, page)
    |> assign(:page_title, gettext("Show page fragment"))
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    model = conn.private[:fragment_model]
    changeset = model.changeset(model.__struct__, :create)
    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, gettext("New page fragment"))
    |> render(:new)
  end

  @doc false
  def create(conn, %{"page_fragment" => page_fragment}) do
    model = conn.private[:fragment_model]
    case model.create(page_fragment, Brando.Utils.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Page fragment created"))
        |> redirect(to: helpers(conn).admin_page_fragment_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("New page fragment"))
        |> assign(:page_fragment, page_fragment)
        |> assign(:changeset, changeset)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:fragment_model]
    changeset =
      model
      |> Brando.repo.get_by!(id: id)
      |> model.encode_data
      |> model.changeset(:update)

    conn
    |> assign(:page_title, gettext("Edit page fragment"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)

  end

  @doc false
  def update(conn, %{"page_fragment" => form_data, "id" => id}) do
    model = conn.private[:fragment_model]
    page_fragment = model |> Brando.repo.get_by!(id: id)
    case model.update(page_fragment, form_data) do
      {:ok, _updated_page_fragment} ->
        conn
        |> put_flash(:notice, gettext("Page fragment updated"))
        |> redirect(to: helpers(conn).admin_page_fragment_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Edit page fragment"))
        |> assign(:page_fragment, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:fragment_model]
    record =
      model
      |> preload(:creator)
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, gettext("Confirm deletion"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:fragment_model]
    record = model |> Brando.repo.get_by!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, gettext("Page fragment deleted"))
    |> redirect(to: helpers(conn).admin_page_fragment_path(conn, :index))
  end
end
