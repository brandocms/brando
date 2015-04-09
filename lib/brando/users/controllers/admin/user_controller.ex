defmodule Brando.Users.Admin.UserController do
  @moduledoc """
  Controller for the Brando Users module.
  """

  use Phoenix.Controller
  import Brando.Plug.Role
  import Brando.Plug.Section

  plug :put_section, "users"
  plug :check_role, :superuser when action in [:new, :create, :delete]
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
  def new(conn, _params) do
    conn
    |> assign(:page_title, "Ny bruker")
    |> render("new.html")
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
        |> put_flash(:error, "Feil i skjema")
        |> assign(:page_title, "Ny bruker")
        |> render(:new)
    end
  end

  @doc false
  def create(conn, _params) do
    conn
    |> assign(:page_title, "Ny bruker")
    |> render(:new)
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
        conn
        |> put_flash(:notice, "Bruker oppdatert.")
        |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:user, form_data)
        |> assign(:errors, errors)
        |> assign(:id, user_id)
        |> put_flash(:error, "Feil i skjema")
        |> assign(:page_title, "Endre bruker")
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
    |> put_flash(:notice, "#{Brando.HTML.Inspect.model_name(record, :singular)} #{model.__str__(record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_user_path(conn, :index))
  end
end