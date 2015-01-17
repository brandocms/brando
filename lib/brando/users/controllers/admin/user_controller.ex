defmodule Brando.Users.Admin.UserController do
  @doc false
  defmacro __using__(options) do
    layout = Dict.fetch! options, :layout
    model = Dict.fetch! options, :model

    quote bind_quoted: [layout: layout, model: model] do
      use Phoenix.Controller
      alias Brando.Users.Model.User

      plug :put_layout, layout
      plug :action

      def index(conn, _params) do
        conn
        |> assign(:users, unquote(model).all)
        |> render("index.html")
      end

      def show(conn, _params) do
        conn
        |> assign(:user, get_session(conn, :current_user))
        |> render("show.html")
      end

      def new(conn, _params) do
        case unquote(model).is_admin?(get_session(conn, :current_user)) do
          true -> conn |> render("new.html")
          false -> conn
        end
      end

      def edit(conn, %{"id" => user_id}) do
        form_data = unquote(model).get(id: String.to_integer(user_id))
        conn
        |> assign(:user, form_data)
        |> assign(:id, user_id)
        |> render(:edit)
      end

      def create(conn, %{"user" => form_data}) do
        require Logger
        created_user = unquote(model).create(form_data)
        case created_user do
          {:ok, created_user} ->
            case User.check_for_uploads(created_user, form_data) do
              {:ok, val} -> conn |> put_flash(:notice, "Bilde lastet opp.")
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
        user = unquote(model).get(id: String.to_integer(user_id))
        case unquote(model).update(user, form_data) do
          {:ok, updated_user} ->
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
        user = unquote(model).get(id: String.to_integer(user_id))
        User.delete(user)
        conn
        |> put_flash(:notice, "Bruker #{user.username} slettet.")
        |> redirect(to: Brando.get_helpers.admin_user_path(conn, :index))
      end

      defoverridable [index: 2, show: 2, new: 2, edit: 2,
                      create: 2, update: 2, destroy: 2]
    end
  end
end