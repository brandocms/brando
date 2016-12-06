defmodule Brando.Admin.UserController do
  @moduledoc """
  Controller for the Brando Users module.
  """
  use Brando.Web, :controller
  alias Brando.{User, Users}
  import Brando.Plug.Authorize
  import Brando.Plug.HTML
  import Brando.Gettext
  import Brando.HTML.Inspect, only: [schema_name: 2, schema_repr: 1]
  import Brando.Utils, only: [helpers: 1, current_user: 1]
  import Brando.Images.Utils, only: [delete_original_and_sized_images: 2]

  plug :put_section, "users"
  plug :scrub_params, "user" when action in [:create, :update]
  plug :authorize, :superuser when action in [:new, :create, :delete, :edit, :update]

  @doc false
  def index(conn, _params) do
    users = Users.get_users()

    conn
    |> assign(:users, users)
    |> assign(:page_title, gettext("Index - users"))
    |> render("index.html")
  end

  @doc false
  def show(conn, %{"id" => user_id}) do
    user = Users.get_user_by!(id: user_id)

    conn
    |> assign(:user, user)
    |> assign(:page_title, gettext("Show user"))
    |> render("show.html")
  end

  @doc false
  def profile(conn, _params) do
    session_user = current_user(conn)
    user         = Users.get_user_by!(id: session_user.id)

    conn
    |> assign(:user, user)
    |> assign(:page_title, gettext("Profile"))
    |> render("show.html")
  end

  @doc false
  def profile_edit(conn, _params) do
    session_user = current_user(conn)
    changeset =
      Users.get_user_by!(id: session_user.id)
      |> User.changeset(:update)

    conn
    |> assign(:changeset, changeset)
    |> assign(:id, session_user.id)
    |> assign(:page_title, gettext("Edit profile"))
    |> render(:profile_edit)
  end

  @doc false
  def profile_update(conn, %{"user" => form_data}) do
    session_user = current_user(conn)
    case Users.update_user(session_user.id, form_data) do
      {:ok, updated_user} ->
        conn =
          if session_user.id == updated_user.id do
            put_session(conn, :current_user, Map.drop(updated_user, [:password]))
          else
            conn
          end

        conn
        |> put_flash(:notice, gettext("Profile updated"))
        |> redirect(to: helpers(conn).admin_user_path(conn, :profile))

      {:error, changeset} ->
        conn
        |> assign(:user, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, session_user.id)
        |> assign(:page_title, gettext("Edit profile"))
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:profile_edit)
    end
  end

  @doc false
  def new(conn, _params) do
    changeset = User.changeset(%User{}, :create)

    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, gettext("New user"))
    |> render("new.html")
  end

  @doc false
  def create(conn, %{"user" => form_data}) do
    case Users.create_user(form_data) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("User created"))
        |> redirect(to: helpers(conn).admin_user_path(conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> assign(:page_title, gettext("New user"))
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => user_id}) do
    user = Users.get_user_by!(id: user_id)
    changeset = User.changeset(user, :update)

    conn
    |> assign(:changeset, changeset)
    |> assign(:id, user_id)
    |> assign(:page_title, gettext("Edit user"))
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"user" => form_data, "id" => user_id}) do
    case Users.update_user(user_id, form_data) do
      {:ok, updated_user} ->
        conn =
          if current_user(conn).id == String.to_integer(user_id) do
            put_session(conn, :current_user, Map.drop(updated_user, [:password]))
          else
            conn
          end

        conn
        |> put_flash(:notice, gettext("User updated"))
        |> redirect(to: helpers(conn).admin_user_path(conn, :index))

      {:error, changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> assign(:id, user_id)
        |> assign(:page_title, gettext("Edit user"))
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => user_id}) do
    record = Users.get_user_by!(id: user_id)

    conn
    |> assign(:record, record)
    |> assign(:page_title, gettext("Confirm deletion"))
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => user_id}) do
    record = Users.get_user_by!(id: user_id)

    {:ok, _} = delete_original_and_sized_images(record, :avatar)
    Users.delete_user(record)

    conn
    |> put_flash(:notice, "#{schema_name(record, :singular)} #{schema_repr(record)} #{gettext("deleted")}")
    |> redirect(to: helpers(conn).admin_user_path(conn, :index))
  end
end
