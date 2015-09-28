defmodule <%= application_module %>.LockdownController do
  use <%= application_module %>.Web, :controller
  import Ecto.Query

  def index(conn, params) do
    conn
    |> put_layout({<%= application_module %>.LayoutView, "lockdown.html"})
    |> render("index.html")
  end
end
