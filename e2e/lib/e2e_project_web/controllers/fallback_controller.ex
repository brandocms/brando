defmodule E2eProjectWeb.FallbackController do
  use BrandoWeb, :controller

  def call(conn, {:error, {_, :not_found}}) do
    conn
    |> put_status(:not_found)
    |> put_layout(false)
    |> put_view(html: E2eProjectWeb.ErrorHTML)
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_layout(false)
    |> put_view(html: E2eProjectWeb.ErrorHTML)
    |> render(:"401")
  end
end
