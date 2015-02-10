defmodule Brando.News.Admin.PostController do
  @moduledoc """
  Controller for the Brando News module.
  """

  use Phoenix.Controller
  import Brando.Plugs.Role
  import Brando.Util, only: [add_css: 2, add_js: 2]

  plug :check_role, :superuser when action in [:new, :create, :delete]
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
    require Logger
    Logger.debug(inspect(Poison.decode!(post["body"])))
    conn
    |> add_css("villain/villain.css")
    |> add_js("villain/villain.js")
    |> assign(:post, post)
    |> render(:new)
  end
end