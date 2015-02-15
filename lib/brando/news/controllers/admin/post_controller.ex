defmodule Brando.News.Admin.PostController do
  @moduledoc """
  Controller for the Brando News module.
  """
  alias Brando.Images.Model.Image
  alias Brando.Images.Model.ImageSeries
  use Phoenix.Controller
  use Villain.Controller,
    image_model: Image,
    series_model: ImageSeries
  import Brando.Utils, only: [add_css: 2, add_js: 2]

  plug :action

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    conn
    |> assign(:posts, model.all)
    |> render(:index)
  end

  @doc false
  def show(conn, %{"id" => id}) do
    model = conn.private[:model]
    conn
    |> assign(:post, model.get(id: id))
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    conn
    |> add_css("villain/villain.css")
    |> add_js("villain/villain.js")
    |> render(:new)
  end

  @doc false
  def create(conn, %{"post" => post}) do
    model = conn.private[:model]
    case model.create(post, Brando.HTML.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, "Post opprettet.")
        |> redirect(to: router_module(conn).__helpers__.admin_post_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:post, post)
        |> assign(:errors, errors)
        |> add_css("villain/villain.css")
        |> add_js("villain/villain.js")
        |> put_flash(:error, "Feil i skjema")
        |> render(:new)
    end
  end

  @doc false
  def create(conn, _params) do
    conn |> render(:new)
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:model]
    if post = model.get(id: String.to_integer(id)) do
      conn
      |> add_css("villain/villain.css")
      |> add_js("villain/villain.js")
      |> assign(:post, post)
      |> assign(:id, id)
      |> render(:edit)
    else
      conn |> put_status(:not_found) |> render(:not_found)
    end
  end

  @doc false
  def update(conn, %{"post" => form_data, "id" => id}) do
    model = conn.private[:model]
    post = model.get(id: String.to_integer(id))
    case model.update(post, form_data) do
      {:ok, _updated_post} ->
        conn
        |> put_flash(:notice, "Post oppdatert.")
        |> redirect(to: router_module(conn).__helpers__.admin_post_path(conn, :index))
      {:error, errors} ->
        conn
        |> add_css("villain/villain.css")
        |> add_js("villain/villain.js")
        |> assign(:post, form_data)
        |> assign(:errors, errors)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:model]
    post = model.get(id: String.to_integer(id))
    model.delete(post)
    conn
    |> put_flash(:notice, "Post #{post.header} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_post_path(conn, :index))
  end

  @doc false
  def not_found(conn, _params) do
    render conn, "not_found"
  end

end