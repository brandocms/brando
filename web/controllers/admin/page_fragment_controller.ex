defmodule Brando.Admin.PageFragmentController do
  @moduledoc """
  Controller for the Brando PageFragment module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries

  import Brando.Plug.Section
  import Ecto.Query

  plug :put_section, "page_fragments"
  plug :scrub_params, "page_fragment" when action in [:create, :update]

  @doc false
  def index(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    conn
    |> assign(:page_fragments, model.all)
    |> assign(:page_title, t!(language, "title.index"))
    |> render(:index)
  end

  @doc false
  def show(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    page =
      model
      |> preload(:creator)
      |> Brando.repo.get_by!(id: id)
    conn
    |> assign(:page_fragment, page)
    |> assign(:page_title, t!(language, "title.show"))
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    changeset = model.changeset(model.__struct__, :create)
    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, t!(language, "title.new"))
    |> render(:new)
  end

  @doc false
  def create(conn, %{"page_fragment" => page_fragment}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    case model.create(page_fragment, Brando.HTML.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, t!(language, "flash.created"))
        |> redirect(to: router_module(conn).__helpers__.admin_page_fragment_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.new"))
        |> assign(:page_fragment, page_fragment)
        |> assign(:changeset, changeset)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    changeset =
      model
      |> Brando.repo.get_by!(id: id)
      |> model.encode_data
      |> model.changeset(:update)

    conn
    |> assign(:page_title, t!(language, "title.edit"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)

  end

  @doc false
  def update(conn, %{"page_fragment" => form_data, "id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    page_fragment = model |> Brando.repo.get_by!(id: id)
    case model.update(page_fragment, form_data) do
      {:ok, _updated_page_fragment} ->
        conn
        |> put_flash(:notice, t!(language, "flash.updated"))
        |> redirect(to: router_module(conn).__helpers__.admin_page_fragment_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.edit"))
        |> assign(:page_fragment, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    record =
      model
      |> preload(:creator)
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, t!(language, "title.delete_confirm"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:fragment_model]
    record = model |> Brando.repo.get_by!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, t!(language, "flash.deleted"))
    |> redirect(to: router_module(conn).__helpers__.admin_page_fragment_path(conn, :index))
  end

  locale "no", [
    title: [
      index: "Sidefragmentoversikt",
      show: "Vis fragment",
      new: "Ny fragment",
      edit: "Endre fragment",
      delete_confirm: "Bekreft sletting av fragment",
    ],
    flash: [
      form_error: "Feil i skjema",
      updated: "Sidefragment oppdatert",
      created: "Sidefragment opprettet",
      deleted: "Sidefragment slettet"
    ]
  ]

  locale "en", [
    title: [
      index: "Index – Page fragments",
      show: "Show page fragment",
      new: "New page fragment",
      edit: "Edit page fragment",
      delete_confirm: "Confirm page fragment deletion",
    ],
    flash: [
      form_error: "Error(s) in form",
      updated: "Page fragment updated",
      created: "Page fragment created",
      deleted: "Page fragment deleted"
    ]
  ]
end