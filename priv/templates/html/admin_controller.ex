defmodule <%= admin_module %>Controller do
  use <%= base %>.Web, :controller
  <%= if villain do %>  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries<% end %>
  <%= if image_field do %>  import Brando.Plug.Uploads<% end %>
  alias <%= module %>

  plug :scrub_params, <%= inspect singular %> when action in [:create, :update]
  <%= if image_field do %>plug :check_for_uploads, {<%= inspect singular %>, <%= module %>} when action in [:create, :update]<% end %>

  def index(conn, _params) do
    <%= plural %> = Repo.all(<%= alias %>)
    render(conn, "index.html", <%= plural %>: <%= plural %>)
  end

  def new(conn, _params) do
    changeset = <%= alias %>.changeset(%<%= alias %>{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{<%= inspect singular %> => <%= singular %>_params}) do
    changeset = <%= alias %>.changeset(%<%= alias %>{}, <%= singular %>_params)

    if changeset.valid? do
      Repo.insert!(changeset)

      conn
      |> put_flash(:info, "<%= no_singular %> opprettet.")
      |> redirect(to: <%= admin_path %>_path(conn, :index))
    else
      render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    <%= singular %> = Repo.get!(<%= alias %>, id)
    render(conn, "show.html", <%= singular %>: <%= singular %>)
  end

  def edit(conn, %{"id" => id}) do
    <%= singular %> = Repo.get!(<%= alias %>, id)
    changeset = <%= alias %>.changeset(<%= singular %>)
    render(conn, "edit.html", <%= singular %>: <%= singular %>, changeset: changeset)
  end

  def update(conn, %{"id" => id, <%= inspect singular %> => <%= singular %>_params}) do
    <%= singular %> = Repo.get!(<%= alias %>, id)
    changeset = <%= alias %>.changeset(<%= singular %>, <%= singular %>_params)

    if changeset.valid? do
      Repo.update!(changeset)

      conn
      |> put_flash(:info, "<%= no_singular %> ble oppdatert.")
      |> redirect(to: <%= admin_path %>_path(conn, :index))
    else
      render(conn, "edit.html", <%= singular %>: <%= singular %>, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    <%= singular %> = Repo.get!(<%= alias %>, id)
    <%= alias %>.delete(<%= singular %>)

    conn
    |> put_flash(:info, "<%= no_singular %> ble slettet")
    |> redirect(to: <%= admin_path %>_path(conn, :index))
  end

  def delete_confirm(conn, %{"id" => id}) do
    record = Repo.get!(<%= alias %>, id)
    conn
    |> assign(:record, record)
    |> assign(:page_title, "Bekreft sletting")
    |> render(:delete_confirm)
  end
end