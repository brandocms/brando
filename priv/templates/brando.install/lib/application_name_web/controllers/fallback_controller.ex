defmodule <%= application_module %>Web.FallbackController do
  use <%= application_module %>Web, :controller

  def call(conn, {:error, {_, :not_found}}) do
    conn
    |> put_status(:not_found)
    |> put_layout(false)
    |> put_view(<%= application_module %>Web.ErrorView)
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_layout(false)
    |> put_view(<%= application_module %>Web.ErrorView)
    |> render(:"401")
  end
end
