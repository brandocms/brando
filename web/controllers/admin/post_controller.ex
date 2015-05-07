defmodule Brando.Admin.PostController do
  @moduledoc """
  Controller for the Brando News module.
  """
  use Brando.Web, :controller
  use Brando.Villain.Controller,
    image_model: Brando.Image,
    series_model: Brando.ImageSeries

  import Brando.Plug.Section
  import Brando.HTML.Inspect, only: [model_name: 2]

  plug :put_section, "news"
  plug :scrub_params, "post" when action in [:create, :update]
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
        |> put_flash(:error, "Feil i skjema")
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:model]
    if post = model.get(id: id) do
      post = post
      |> model.encode_data
      conn
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
        |> assign(:post, form_data)
        |> assign(:errors, errors)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = model.get!(id: id)
    conn
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = model.get!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, "#{model_name(record, :singular)} #{model.__repr__(record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_post_path(conn, :index))
  end
end