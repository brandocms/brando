defmodule Brando.Admin.UserController do
  @moduledoc """
  Controller for the Brando Users module.
  """

  use Brando.Web, :controller
  use Linguist.Vocabulary
  import Brando.Plug.Authorize
  import Brando.Plug.Section
  import Brando.Plug.Uploads
  import Brando.HTML.Inspect, only: [model_name: 3]
  import Brando.HTML, only: [current_user: 1]

  plug :put_section, "users"
  plug :scrub_params, "user" when action in [:create, :update]
  plug :check_for_uploads, {"user", Brando.User} when action in [:create, :profile_update, :update]
  plug :authorize, :superuser when action in [:new, :create, :delete, :edit, :update]

  @doc false
  def index(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    conn
    |> assign(:users, model |> model.order_by_id |> Brando.repo.all)
    |> assign(:page_title, t!(language, "title.index"))
    |> render("index.html")
  end

  @doc false
  def show(conn, %{"id" => user_id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    conn
    |> assign(:user, Brando.repo.get_by!(model, id: user_id))
    |> assign(:page_title, t!(language, "title.show"))
    |> render("show.html")
  end

  @doc false
  def profile(conn, _params) do
    language = Brando.I18n.get_language(conn)
    conn
    |> assign(:user, get_session(conn, :current_user))
    |> assign(:page_title, t!(language, "title.profile"))
    |> render("show.html")
  end

  @doc false
  def profile_edit(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    user_id = current_user(conn).id
    changeset =
      Brando.repo.get!(model, user_id)
      |> model.changeset(:update)
    conn
    |> assign(:changeset, changeset)
    |> assign(:id, user_id)
    |> assign(:page_title, t!(language, "title.edit"))
    |> render(:profile_edit)
  end

  @doc false
  def profile_update(conn, %{"user" => form_data}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    user_id = current_user(conn).id
    user = Brando.repo.get_by!(model, id: user_id)

    case model.update(user, form_data) do
      {:ok, updated_user} ->
        if current_user(conn).id == user_id do
          conn = conn |> put_session(:current_user, Map.drop(updated_user, [:password]))
        end
        conn
        |> put_flash(:notice, t!(language, "flash.updated"))
        |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :profile))
      {:error, changeset} ->
        conn
        |> assign(:user, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, user_id)
        |> assign(:page_title, t!(language, "title.edit"))
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:profile_edit)
    end
  end

  @doc false
  def new(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    changeset = model.changeset(model.__struct__, :create)
    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, t!(language, "title.new"))
    |> render("new.html")
  end

  @doc false
  def create(conn, %{"user" => form_data}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    case model.create(form_data) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, t!(language, "flash.created"))
        |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> assign(:page_title, t!(language, "title.new"))
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => user_id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    changeset =
      Brando.repo.get!(model, user_id)
      |> model.changeset(:update)

    conn
    |> assign(:changeset, changeset)
    |> assign(:id, user_id)
    |> assign(:page_title, t!(language, "title.edit"))
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"user" => form_data, "id" => user_id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    user = Brando.repo.get_by!(model, id: user_id)

    case model.update(user, form_data) do
      {:ok, updated_user} ->
        if Brando.HTML.current_user(conn).id == String.to_integer(user_id) do
          conn = put_session(conn, :current_user, Map.drop(updated_user, [:password]))
        end

        conn
        |> put_flash(:notice, t!(language, "flash.updated"))
        |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> assign(:id, user_id)
        |> assign(:page_title, t!(language, "title.edit"))
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => user_id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    record = Brando.repo.get_by!(model, id: user_id)
    conn
    |> assign(:record, record)
    |> assign(:page_title, t!(language, "title.delete_confirm"))
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => user_id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    record = Brando.repo.get_by!(model, id: user_id)
    model.delete(record)
    conn
    |> put_flash(:notice, "#{model_name(language, record, :singular)} #{model.__repr__(language, record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
  end

  locale "no", [
    title: [
      index: "Brukeroversikt",
      show: "Vis bruker",
      new: "Ny bruker",
      edit: "Endre bruker",
      profile: "Profil",
      delete_confirm: "Bekreft sletting av bruker",
    ],
    flash: [
      form_error: "Feil i skjema",
      updated: "Bruker oppdatert",
      created: "Bruker opprettet"
    ]
  ]

  locale "en", [
    title: [
      index: "Index – Users",
      show: "Show user",
      new: "New user",
      edit: "Edit user",
      profile: "Profile",
      delete_confirm: "Confirm user deletion",
    ],
    flash: [
      form_error: "Error(s) in form",
      updated: "User updated",
      created: "User created"
    ]
  ]
end