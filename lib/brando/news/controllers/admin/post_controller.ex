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
    created_user = model.create(post, Brando.HTML.current_user(conn))

    conn
    |> add_css("villain/villain.css")
    |> add_js("villain/villain.js")
    |> assign(:post, post)
    |> render(:new)
  end
end