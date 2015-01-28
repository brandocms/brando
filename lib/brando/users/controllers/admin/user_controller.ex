defmodule Brando.Users.Admin.UserController do
  @moduledoc """
  This is a boilerplate UserController.
  """

  use Phoenix.Controller

  import Brando.Plugs.Role
  plug :check_role, :superuser when action in [:new, :create, :destroy]
  plug :action

  def init(options) do
    options
  end

  def call(conn, opts) do
    conn = conn
    |> put_layout(opts[:layout])
    |> assign(:model, opts[:model])
    super(conn, action_name(conn))
  end

  def index(conn, _params) do
    model = conn.assigns[:model]
    conn
    |> assign(:users, model.all)
    |> render("index.html")
  end

  def show(conn, _params) do
    conn
    |> assign(:user, get_session(conn, :current_user))
    |> render("show.html")
  end

  def new(conn, _params) do
    conn |> render("new.html")
  end

  def edit(conn, %{"id" => user_id}) do
    model = conn.assigns[:model]
    form_data = model.get(id: String.to_integer(user_id))
    conn
    |> assign(:user, form_data)
    |> assign(:id, user_id)
    |> render(:edit)
  end

  def create(conn, %{"user" => form_data}) do
    model = conn.assigns[:model]
    created_user = model.create(form_data)
    case created_user do
      {:ok, created_user} ->
        case model.check_for_uploads(created_user, form_data) do
          {:ok, _val} -> conn |> put_flash(:notice, "Bilde lastet opp.")
          {:errors, _errors} -> nil
          :nouploads -> nil
        end
        conn
        |> put_flash(:notice, "Bruker opprettet.")
        |> redirect(to: Brando.get_helpers().admin_user_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:user, form_data)
        |> assign(:errors, errors)
        |> put_flash(:error, "Feil i skjema")
        |> render(:new)
    end
  end

  def create(conn, _params) do
    conn |> render(:new)
  end

  def update(conn, %{"user" => form_data, "id" => user_id}) do
    model = conn.assigns[:model]
    user = model.get(id: String.to_integer(user_id))
    case model.update(user, form_data) do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:notice, "Bruker oppdatert.")
        |> redirect(to: Brando.get_helpers.admin_user_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:user, form_data)
        |> assign(:errors, errors)
        |> assign(:id, user_id)
        |> render(:edit)
    end
  end

  def destroy(conn, %{"id" => user_id}) do
    model = conn.assigns[:model]
    user = model.get(id: String.to_integer(user_id))
    model.delete(user)
    conn
    |> put_flash(:notice, "Bruker #{user.username} slettet.")
    |> redirect(to: Brando.get_helpers.admin_user_path(conn, :index))
  end
end