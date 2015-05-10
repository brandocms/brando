defmodule Brando.Admin.UserController do
  @moduledoc """
  Controller for the Brando Users module.
  """

  use Brando.Web, :controller
  import Brando.Plug.Authorize
  import Brando.Plug.Section
  import Brando.HTML.Inspect, only: [model_name: 2]
  import Brando.HTML, only: [current_user: 1]

  plug :put_section, "users"
  plug :scrub_params, "user" when action in [:create, :update]
  plug :authorize, :superuser when action in [:new, :create, :delete, :edit, :update]
  plug :action

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    conn
    |> assign(:users, model.all)
    |> assign(:page_title, "Brukeroversikt")
    |> render("index.html")
  end

  @doc false
  def show(conn, %{"id" => user_id}) do
    model = conn.private[:model]
    conn
    |> assign(:user, model.get!(id: user_id))
    |> assign(:page_title, "Vis bruker")
    |> render("show.html")
  end

  @doc false
  def profile(conn, _params) do
    conn
    |> assign(:user, get_session(conn, :current_user))
    |> assign(:page_title, "Brukerprofil")
    |> render("show.html")
  end

  @doc false
  def profile_edit(conn, _params) do
    model = conn.private[:model]
    user_id = current_user(conn).id
    form_data = model.get(id: user_id)
    conn
    |> assign(:user, form_data)
    |> assign(:id, user_id)
    |> assign(:page_title, "Endre profil")
    |> render(:profile_edit)
  end

  @doc false
  def profile_update(conn, %{"user" => form_data}) do
    model = conn.private[:model]
    user_id = current_user(conn).id
    user = model.get(id: user_id)

    case model.update(user, form_data) do
      {:ok, updated_user} ->
        case model.check_for_uploads(updated_user, form_data) do
          {:ok, _val} -> conn |> put_flash(:notice, "Bilde lastet opp.")
          {:errors, _errors} -> nil
          [] -> nil
        end
        if current_user(conn).id == user_id do
          conn = put_session(conn, :current_user, Map.drop(updated_user, [:password]))
        end

        conn
        |> put_flash(:notice, "Profil oppdatert.")
        |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :profile))
      {:error, errors} ->
        conn
        |> assign(:user, form_data)
        |> assign(:errors, errors)
        |> assign(:id, user_id)
        |> assign(:page_title, "Endre profil")
        |> put_flash(:error, "Feil i skjema")
        |> render(:profile_edit)
    end
  end

  @doc false
  def new(conn, _params) do
    conn
    |> assign(:page_title, "Ny bruker")
    |> render("new.html")
  end

  @doc false
  def create(conn, %{"user" => form_data}) do
    model = conn.private[:model]
    created_user = model.create(form_data)
    case created_user do
      {:ok, created_user} ->
        case model.check_for_uploads(created_user, form_data) do
          {:ok, _val} -> conn |> put_flash(:notice, "Bilde lastet opp.")
          {:errors, _errors} -> nil
          [] -> nil
        end
        conn
        |> put_flash(:notice, "Bruker opprettet.")
        |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:user, form_data)
        |> assign(:errors, errors)
        |> assign(:page_title, "Ny bruker")
        |> put_flash(:error, "Feil i skjema")
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => user_id}) do
    model = conn.private[:model]
    form_data = model.get(id: String.to_integer(user_id))
    conn
    |> assign(:user, form_data)
    |> assign(:id, user_id)
    |> assign(:page_title, "Endre bruker")
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"user" => form_data, "id" => user_id}) do
    model = conn.private[:model]
    user = model.get(id: String.to_integer(user_id))

    case model.update(user, form_data) do
      {:ok, updated_user} ->
        case model.check_for_uploads(updated_user, form_data) do
          {:ok, _val} -> conn |> put_flash(:notice, "Bilde lastet opp.")
          {:errors, _errors} -> nil
          [] -> nil
        end
        if Brando.HTML.current_user(conn).id == String.to_integer(user_id) do
          conn = put_session(conn, :current_user, Map.drop(updated_user, [:password]))
        end

        conn
        |> put_flash(:notice, "Bruker oppdatert.")
        |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:user, form_data)
        |> assign(:errors, errors)
        |> assign(:id, user_id)
        |> assign(:page_title, "Endre bruker")
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = model.get!(id: id)
    conn
    |> assign(:record, record)
    |> assign(:page_title, "Bekreft sletting")
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = model.get!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, "#{model_name(record, :singular)} #{model.__repr__(record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
  end
end