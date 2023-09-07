defmodule BrandoWeb.FallbackController do
  use Phoenix.Controller,
    namespace: Brando.config(:web_module),
    formats: [:html, :json]

  alias Brando.Sites.Redirects

  @doc """
  Handle errors
  """
  def call(%{assigns: %{language: language}} = conn, {:error, {_, :not_found}}) do
    case Redirects.test_redirect(conn.path_info, language) do
      {:error, {:redirects, :no_match}} ->
        conn
        |> put_status(:not_found)
        |> put_layout(false)
        |> put_view(Brando.endpoint().config(:render_errors)[:formats])
        |> render(:"404")

      {:ok, {:redirect, {_url, 410}}} ->
        # 410 GONE
        conn
        |> resp(410, "Gone.")
        |> halt()

      {:ok, {:redirect, {url, code}}} ->
        conn
        |> put_resp_header("location", url)
        |> resp(code, "You are being redirected.")
        |> halt()
    end
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_layout(false)
    |> put_view(Brando.endpoint().config(:render_errors)[:formats])
    |> render(:"401")
  end
end
