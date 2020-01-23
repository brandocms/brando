defmodule <%= module %>Controller do
  use <%= base %>Web, :controller
  alias <%= base %>.<%= domain %>
  alias <%= base %>Web.FallbackController
  action_fallback FallbackController

  @doc false
  def index(conn, _params) do
    {:ok, <%= plural %>} = <%= domain %>.list_<%= plural %>()

    conn
    |> assign(:<%= plural %>, <%= plural %>)
    |> put_section(:<%= snake_domain %>)
    |> render(:index)
  end

  @doc false
  def show(conn, %{"slug" => slug}) do
    with {:ok, <%= singular %>} <- <%= domain %>.get_<%= singular %>(slug: slug) do
      conn
      |> assign(:entry, <%= singular %>)
      |> put_section(:<%= singular %>)
      |> render(:show)
    end
  end
end
