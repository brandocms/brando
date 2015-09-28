defmodule Brando.Admin.PostController do
  @moduledoc """
  Controller for the Brando News module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries

  import Brando.Plug.Section

  plug :put_section, "news"
  plug :scrub_params, "post" when action in [:create, :update]

  @doc false
  def index(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    posts =
      model
      |> model.order
      |> model.preload_creator
      |> Brando.repo.all

    conn
    |> assign(:page_title, t!(language, "title.index"))
    |> assign(:posts, posts)
    |> render(:index)
  end

  @doc false
  def show(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    post =
      model
      |> model.preload_creator
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, t!(language, "title.show"))
    |> assign(:post, post)
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    changeset = model.changeset(model.__struct__, :create, :empty)

    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, t!(language, "title.new"))
    |> render(:new)
  end

  @doc false
  def create(conn, %{"post" => post}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    case model.create(post, Brando.Utils.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, t!(language, "flash.created"))
        |> redirect(to: router_module(conn).__helpers__.admin_post_path(conn,
                                                                        :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.new"))
        |> assign(:post, post)
        |> assign(:changeset, changeset)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    changeset =
      model
      |> Brando.repo.get!(id)
      |> model.encode_data
      |> model.changeset(:update)

    conn
    |> assign(:page_title, t!(language, "title.edit"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"post" => form_data, "id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    post = Brando.repo.get_by!(model, id: id)
    case model.update(post, form_data) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, t!(language, "flash.updated"))
        |> redirect(to: router_module(conn).__helpers__.admin_post_path(
                        conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, t!(language, "title.edit"))
        |> assign(:post, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, t!(language, "flash.form_error"))
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    record = Brando.repo.get_by!(model |> model.preload_creator, id: id)

    conn
    |> assign(:page_title, t!(language, "title.delete_confirm"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    language = Brando.I18n.get_language(conn)
    model = conn.private[:model]
    record = Brando.repo.get_by!(model, id: id)
    model.delete(record)

    conn
    |> put_flash(:notice, t!(language, "flash.deleted"))
    |> redirect(to: router_module(conn).__helpers__.admin_post_path(
                    conn, :index))
  end

  locale "no", [
    title: [
      index: "Postoversikt",
      show: "Vis post",
      new: "Ny post",
      edit: "Endre post",
      delete_confirm: "Bekreft sletting av post",
    ],
    flash: [
      form_error: "Feil i skjema",
      updated: "Post oppdatert",
      created: "Post opprettet",
      deleted: "Post slettet"
    ]
  ]

  locale "en", [
    title: [
      index: "Index – Posts",
      show: "Show post",
      new: "New post",
      edit: "Edit post",
      delete_confirm: "Confirm post deletion",
    ],
    flash: [
      form_error: "Error(s) in form",
      updated: "Post updated",
      created: "Post created",
      deleted: "Post deleted"
    ]
  ]
end
