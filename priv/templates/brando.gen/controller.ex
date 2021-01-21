defmodule <%= module %>Controller do
  use <%= web_module %>, :controller
  alias <%= app_module %>.<%= domain %>
  alias <%= web_module %>.FallbackController

  @type conn :: Plug.Conn.t()

  action_fallback FallbackController

  @doc false
  @spec list(conn, map) :: conn
  def list(conn, _params) do
    list_opts = %{}

    with {:ok, <%= plural %>} <- <%= domain %>.list_<%= plural %>(list_opts) do
      conn
      |> assign(:<%= plural %>, <%= plural %>)
      |> put_section("<%= snake_domain %>")
      |> render(:list)
    end
  end

  @doc false
  @spec detail(conn, map) :: {:error, {:<%= singular %>, :not_found}} | conn
  def detail(conn, %{"slug" => slug}) do
    opts = %{matches: %{slug: slug}, status: :published}

    with {:ok, <%= singular %>} <- <%= domain %>.get_<%= singular %>(opts) do
      conn
      |> assign(:entry, <%= singular %>)
      |> put_section("<%= singular %>")
      |> render(:detail)
    end
  end
end
