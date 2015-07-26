defmodule <%= module %>Controller do
  use <%= base %>.Web, :controller
  alias <%= module %>

  def index(conn, _params) do
    <%= plural %> = <%= alias %> |> Brando.repo.all

    conn
    |> assign(:<%= plural %>, <%= plural %>)
    |> assign(:page_title, "<%= no_plural %>")
    |> render("index.html")
  end
end
