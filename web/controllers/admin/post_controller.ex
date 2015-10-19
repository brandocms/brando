defmodule Brando.Admin.PostController do
  @moduledoc """
  Controller for the Brando News module.
  """

  use Linguist.Vocabulary
  use Brando.Web, :controller
  use Brando.Villain, [:controller, [
    image_model: Brando.Image,
    series_model: Brando.ImageSeries]]

  import Brando.Gettext
  import Brando.Plug.HTML

  plug :put_section, "news"
  plug :scrub_params, "post" when action in [:create, :update]

  @doc false
  def index(conn, _params) do
    model = conn.private[:model]
    posts =
      model
      |> model.order
      |> model.preload_creator
      |> Brando.repo.all

    conn
    |> assign(:page_title, gettext("Index - posts"))
    |> assign(:posts, posts)
    |> render(:index)
  end

  @doc false
  def show(conn, %{"id" => id}) do
    model = conn.private[:model]
    post =
      model
      |> model.preload_creator
      |> Brando.repo.get_by!(id: id)

    conn
    |> assign(:page_title, gettext("Show post"))
    |> assign(:post, post)
    |> render(:show)
  end

  @doc false
  def new(conn, _params) do
    model = conn.private[:model]
    changeset = model.changeset(model.__struct__, :create, :empty)

    conn
    |> assign(:changeset, changeset)
    |> assign(:page_title, gettext("New post"))
    |> render(:new)
  end

  @doc false
  def create(conn, %{"post" => post}) do
    model = conn.private[:model]
    case model.create(post, Brando.Utils.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Post created"))
        |> redirect(to: router_module(conn).__helpers__.admin_post_path(conn,
                                                                        :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("New post"))
        |> assign(:post, post)
        |> assign(:changeset, changeset)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:model]
    changeset =
      model
      |> Brando.repo.get!(id)
      |> model.encode_data
      |> model.changeset(:update)

    conn
    |> assign(:page_title, gettext("Edit post"))
    |> assign(:changeset, changeset)
    |> assign(:id, id)
    |> render(:edit)
  end

  @doc false
  def update(conn, %{"post" => form_data, "id" => id}) do
    model = conn.private[:model]
    post = Brando.repo.get_by!(model, id: id)
    case model.update(post, form_data) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, gettext("Post updated"))
        |> redirect(to: router_module(conn).__helpers__.admin_post_path(
                        conn, :index))
      {:error, changeset} ->
        conn
        |> assign(:page_title, gettext("Edit post"))
        |> assign(:post, form_data)
        |> assign(:changeset, changeset)
        |> assign(:id, id)
        |> put_flash(:error, gettext("Errors in form"))
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = Brando.repo.get_by!(model |> model.preload_creator, id: id)

    conn
    |> assign(:page_title, gettext("Confirm deletion"))
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:model]
    record = Brando.repo.get_by!(model, id: id)
    model.delete(record)

    conn
    |> put_flash(:notice, gettext("Post deleted"))
    |> redirect(to: router_module(conn).__helpers__.admin_post_path(
                    conn, :index))
  end
end
