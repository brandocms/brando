defmodule Brando.News.Admin.PostController do
  @moduledoc """
  Controller for the Brando News module.
  """

  use Phoenix.Controller
  import Brando.Util, only: [add_css: 2, add_js: 2]

  plug :action

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    conn
    |> assign(:posts, model.all)
    |> render(:index)
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
    post = model.get(id: String.to_integer(id))
    conn
    |> add_css("villain/villain.css")
    |> add_js("villain/villain.js")
    |> assign(:post, post)
    |> assign(:id, id)
    |> render(:edit)
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

end