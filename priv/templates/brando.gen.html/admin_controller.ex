defmodule <%= admin_module %>Controller do
  use <%= base %>.Admin.Web, :controller
<%= if sequenced do %>  use Brando.Sequence, [:controller, [schema: <%= module %>]]<% end %>
<%= if villain do %>  use Brando.Villain, :controller<% end %>
  alias <%= module %>
  alias <%= base %>.<%= domain %>
<%= if image_field do %>  import Brando.Plug.Uploads<% end %>

  plug :scrub_params, <%= inspect singular %> when action in [:create, :update]
  <%= if image_field do %>plug :check_for_uploads, {<%= inspect singular %>, <%= module %>} when action in [:create, :update]<% end %>

  def index(conn, _params) do
    <%= plural %> = Repo.all(<%= alias %>)

    conn
    |> assign(:page_title, gettext("Index - <%= Phoenix.Naming.humanize(plural) %>"))
    |> render("index.html", <%= plural %>: <%= plural %>)
  end

  def new(conn, _params) do
    changeset = <%= alias %>.changeset(%<%= alias %>{})

    conn
    |> assign(:page_title, gettext("New <%= Phoenix.Naming.humanize(singular) %>"))
    |> render("new.html", changeset: changeset)
  end

  def create(conn, %{<%= inspect singular %> => <%= singular %>_params}) do
    case <%= domain %>.create_<%= singular %>(<%= singular %>_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, gettext("<%= Phoenix.Naming.humanize(singular) %> created"))
        |> redirect(to: <%= admin_path %>_path(conn, :index))
      {:error, changeset} ->
        conn
        |> put_flash(:error, gettext("Errors in form"))
        |> assign(:page_title, gettext("New <%= Phoenix.Naming.humanize(singular) %>"))
        |> render("new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    <%= singular %> = <%= domain %>.get_<%= singular %>_by!(id: id)

    conn
    |> assign(:page_title, gettext("Show <%= Phoenix.Naming.humanize(singular) %>"))
    |> render("show.html", <%= singular %>: <%= singular %>)
  end

  def edit(conn, %{"id" => id}) do
    <%= singular %> = <%= domain %>.get_<%= singular %>_by!(id: id)
    changeset = <%= alias %>.changeset(<%= singular %>)

    conn
    |> assign(:page_title, gettext("Edit <%= Phoenix.Naming.humanize(singular) %>"))
    |> render("edit.html", <%= singular %>: <%= singular %>,
                           changeset: changeset)
  end

  def update(conn, %{"id" => id, <%= inspect singular %> => <%= singular %>_params}) do
    case <%= domain %>.update_<%= singular %>(id, <%= singular %>_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, gettext("<%= Phoenix.Naming.humanize(singular) %> updated"))
        |> redirect(to: <%= admin_path %>_path(conn, :index))
      {:error, changeset} ->
        conn
        |> put_flash(:error, gettext("Errors in form"))
        |> assign(:page_title, gettext("Edit <%= Phoenix.Naming.humanize(singular) %>"))
        |> render("edit.html", <%= singular %>: <%= singular %>,
                               changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    <%= singular %> = Repo.get!(<%= alias %>, id)
    <%= alias %>.delete(<%= singular %>)

    conn
    |> put_flash(:info, gettext("<%= Phoenix.Naming.humanize(singular) %> deleted"))
    |> redirect(to: <%= admin_path %>_path(conn, :index))
  end

  def delete_confirm(conn, %{"id" => id}) do
    record = Repo.get!(<%= alias %>, id)

    conn
    |> assign(:record, record)
    |> assign(:page_title, gettext("Confirm deletion"))
    |> render(:delete_confirm)
  end
end
