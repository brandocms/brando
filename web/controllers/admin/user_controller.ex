defmodule Brando.Admin.UserController do
  @moduledoc """
  Controller for the Brando Users module.
  """

  use Brando.Web, :controller
  import Brando.Plug.Authorize
  import Brando.Plug.HTML
  import Brando.Plug.Uploads
  import Brando.Gettext
  import Brando.HTML.Inspect, only: [schema_name: 2, schema_repr: 1]
  import Brando.Utils, only: [helpers: 1, current_user: 1]
  import Brando.Images.Utils, only: [delete_original_and_sized_images: 2]

  plug :put_section, "users"
  plug :scrub_params, "user" when action in [:create, :update]
  plug :check_for_uploads,
       {"user", Brando.User} when action in [:create, :profile_update, :update]
  plug :authorize,
       :superuser when action in [:new, :create, :delete, :edit, :update]

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    users = model |> model.order_by_id |> Brando.repo.all
    conn
    |> assign(:users, users)
    |> assign(:page_title, gettext("Index - users"))
    |> render("index.html")
  end

  @doc false
  def show(conn, %{"id" => user_id}) do
    model = conn.private[:model]
    conn
    |> assign(:user, Brando.repo.get_by!(model, id: user_id))
    |> assign(:page_title, gettext("Show user"))
    |> render("show.html")
  end

  @doc false
  def profile(conn, _params) do
    session_user = get_session(conn, :current_user)
    model = conn.private[:model]
    conn
    |> assign(:user, Brando.repo.get_by!(model, id: session_user.id))
    |> assign(:page_title, gettext("Profile"))
    |> render("show.html")
  end

  @doc false
  def profile_edit(conn, _params) do
    model = conn.private[:model]
    user_id = current_user(conn).id
    changeset =
      model
      |> Brando.repo.get!(user_id)
      |> model.changeset(:update)

    conn
    |> assign(:changeset, changeset)
    |> assign(:id, user_id)
    |> assign(:page_title, gettext("Edit profile"))
    |> render(:profile_edit)
  end

  @doc false
  def profile_update(conn, %{"user" => form_data}) do
    model = conn.private[:model]
    user_id = current_user(conn).id
    user = Brando.repo.get!(model, user_id)

    case Brando.repo.update(model.update(user, form_data)) do
      {:ok, updated_user} ->
        conn = case current_user(conn).id == user_id do
          true  -> put_session(conn, :current_user, Map.drop(updated_user, [:password]))
          false -> conn
        end
        conn
        |> put_flash(:notice, gettext("Profile updated"))
        |> redirect(to: helpers(conn).admin_user_path(conn, :profile))
      {:error, changeset} ->
        conn
        |> assign(:user, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, user_id)
        |> assign(:page_title, gettext("Edit profile"))
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:profile_edit)
    end
  end

  @doc false
  def new(conn, _params) do
    model = conn.private[:model]
    changeset = model.changeset(model.__struct__, :create)
    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, gettext("New user"))
    |> render("new.html")
  end

  @doc false
  def create(conn, %{"user" => form_data}) do
    model = conn.private[:model]
    case Brando.repo.insert(model.create(form_data)) do
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
    model = conn.private[:model]
    changeset =
      model
      |> Brando.repo.get!(user_id)
      |> model.changeset(:update)

    conn
    |> assign(:changeset, changeset)
    |> assign(:id, user_id)
    |> assign(:page_title, gettext("Edit user"))
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"user" => form_data, "id" => user_id}) do
    model = conn.private[:model]
    user = Brando.repo.get_by!(model, id: user_id)

    case Brando.repo.update(model.update(user, form_data)) do
      {:ok, updated_user} ->
        conn = case current_user(conn).id == String.to_integer(user_id) do
          true -> put_session(conn, :current_user, Map.drop(updated_user, [:password]))
          false -> conn
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
    model = conn.private[:model]
    record = Brando.repo.get!(model, user_id)
    conn
    |> assign(:record, record)
    |> assign(:page_title, gettext("Confirm deletion"))
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => user_id}) do
    model = conn.private[:model]
    record = Brando.repo.get!(model, user_id)

    delete_original_and_sized_images(record, :avatar)
    Brando.repo.delete!(record)

    conn
    |> put_flash(:notice, "#{schema_name(record, :singular)} #{schema_repr(record)} #{gettext("deleted")}")
    |> redirect(to: helpers(conn).admin_user_path(conn, :index))
  end
end
