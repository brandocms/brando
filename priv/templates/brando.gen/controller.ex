defmodule <%= inspect controller_module %> do
  use <%= web_module %>, :controller

  plug Brando.Plug.Tenant

  def index(conn, _params) do
    {:ok, entries} = <%= inspect context_module %>.list_<%= plural %>(<%= if status, do: "%{status: :published}", else: "%{}" %>)
    render(conn, :index, entries: entries)
  end

  def show(conn, %{"id" => id}) do
    case <%= inspect context_module %>.get_<%= singular %>(%{matches: %{id: id}<%= if status, do: ", status: :published" %>}) do
      {:ok, entry} -> render(conn, :show, entry: entry)
      {:error, {_, :not_found}} -> send_resp(conn, 404, "Not found")
    end
  end
end
