defmodule Brando.FallbackController do
  use Brando.Web, :controller

  @doc """
  Handle errors
  """
  def call(conn, {:error, {_, :not_found}}) do
    conn
    |> put_status(:not_found)
    |> put_layout(false)
    |> put_view(Module.concat(Brando.config(:web_module), ErrorView))
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_layout(false)
    |> put_view(Module.concat(Brando.config(:web_module), ErrorView))
    |> render(:"401")
  end
end
