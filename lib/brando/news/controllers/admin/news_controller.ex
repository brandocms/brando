defmodule Brando.News.Admin.NewsController do
  @moduledoc """
  Controller for the Brando News module.
  """

  use Phoenix.Controller
  import Brando.Plugs.Role
  import Brando.Util, only: [add_css: 2, add_js: 2]

  plug :check_role, :superuser when action in [:new, :create, :delete]
  plug :action

  @doc false
  def new(conn, _params) do
    conn
    |> add_css("villain/villain-min.css")
    |> add_js("villain/villain-min.js")
    |> render("new.html")
  end
end