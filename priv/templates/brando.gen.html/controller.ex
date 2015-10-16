defmodule <%= module %>Controller do
  use <%= base %>.Web, :controller
  alias <%= module %>

  def index(conn, _params) do
    <%= plural %> = Brando.repo.all(<%= alias %>)

    conn
    |> assign(:<%= plural %>, <%= plural %>)
    |> assign(:page_title, "<%= plural %>")
    |> render("index.html")
  end
end
