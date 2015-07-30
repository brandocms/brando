defmodule <%= admin_module %>Controller do
  use <%= base %>.Web, :controller
<%= if villain do %>  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries<% end %>
<%= if image_field do %>  import Brando.Plug.Uploads<% end %>
  alias <%= module %>

  plug :scrub_params, <%= inspect singular %> when action in [:create, :update]
  <%= if image_field do %>plug :check_for_uploads, {<%= inspect singular %>, <%= module %>} when action in [:create, :update]<% end %>

  def index(conn, params) do
    language = Brando.I18n.get_language(conn)
    <%= plural %> = Repo.all(<%= alias %>)
    conn
    |> assign(:page_title, t!(language, "title.index"))
    |> render("index.html", <%= plural %>: <%= plural %>)
  end

  def new(conn, _params) do
    language = Brando.I18n.get_language(conn)
    changeset = <%= alias %>.changeset(%<%= alias %>{})
    conn
    |> assign(:page_title, t!(language, "title.new"))
    |> render("new.html", changeset: changeset)
  end

  def create(conn, %{<%= inspect singular %> => <%= singular %>_params}) do
    language = Brando.I18n.get_language(conn)
    changeset = <%= alias %>.changeset(%<%= alias %>{}, <%= singular %>_params)

    if changeset.valid? do
      Repo.insert!(changeset)

      conn
      |> put_flash(:info, t!(language, "flash.created"))
      |> redirect(to: <%= admin_path %>_path(conn, :index))
    else
      conn
      |> assign(:page_title, t!(language, "title.new"))
      |> render("new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    <%= singular %> = Repo.get!(<%= alias %>, id)
    conn
    |> assign(:page_title, t!(language, "title.show"))
    |> render("show.html", <%= singular %>: <%= singular %>)
  end

  def edit(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    <%= singular %> = Repo.get!(<%= alias %>, id)
    changeset = <%= alias %>.changeset(<%= singular %>)
    conn
    |> assign(:page_title, t!(language, "title.edit"))
    |> render("edit.html", <%= singular %>: <%= singular %>, changeset: changeset)
  end

  def update(conn, %{"id" => id, <%= inspect singular %> => <%= singular %>_params}) do
    language = Brando.I18n.get_language(conn)
    <%= singular %> = Repo.get!(<%= alias %>, id)
    changeset = <%= alias %>.changeset(<%= singular %>, <%= singular %>_params)

    if changeset.valid? do
      Repo.update!(changeset)

      conn
      |> put_flash(:info, t!(language, "flash.updated"))
      |> redirect(to: <%= admin_path %>_path(conn, :index))
    else
      conn
      |> assign(:page_title, t!(language, "title.edit"))
      |> render("edit.html", <%= singular %>: <%= singular %>, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    <%= singular %> = Repo.get!(<%= alias %>, id)
    <%= alias %>.delete(<%= singular %>)

    conn
    |> put_flash(:info, t!(language, "flash.deleted"))
    |> redirect(to: <%= admin_path %>_path(conn, :index))
  end

  def delete_confirm(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    record = Repo.get!(<%= alias %>, id)
    conn
    |> assign(:record, record)
    |> assign(:page_title, t!(language, "title.delete_confirm"))
    |> render(:delete_confirm)
  end

  locale "no", [
    title: [
      index: "<%= String.capitalize(no_singular) %>oversikt",
      show: "Vis <%= no_singular %>",
      new: "Ny <%= no_singular %>",
      edit: "Endre <%= no_singular %>",
      delete_confirm: "Bekreft sletting av <%= no_singular %>",
    ],
    flash: [
      form_error: "Feil i skjema",
      updated: "<%= String.capitalize(no_singular) %> oppdatert",
      created: "<%= String.capitalize(no_singular) %> opprettet",
      deleted: "<%= String.capitalize(no_singular) %> slettet"
    ]
  ]

  locale "en", [
    title: [
      index: "Index – <%= plural %>",
      show: "Show <%= singular %>",
      new: "New <%= singular %>",
      edit: "Edit <%= singular %>",
      delete_confirm: "Confirm <%= singular %> deletion",
    ],
    flash: [
      form_error: "Error(s) in form",
      updated: "<%= String.capitalize(singular) %> updated",
      created: "<%= String.capitalize(singular) %> created"
      deleted: "<%= String.capitalize(singular) %> deleted"
    ]
  ]
end