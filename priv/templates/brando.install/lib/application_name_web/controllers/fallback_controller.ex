defmodule <%= application_module %>Web.FallbackController do
  use <%= application_module %>Web, :controller

  def call(conn, {:error, {_, :not_found}}) do
    conn
    |> put_status(:not_found)
    |> put_layout(false)
    |> render(<%= application_module %>.ErrorView, :"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_layout(false)
    |> render(<%= application_module %>.ErrorView, :"401")
  end
end
