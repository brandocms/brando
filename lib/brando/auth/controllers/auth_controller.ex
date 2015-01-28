defmodule Brando.Auth.AuthController do
  use Phoenix.Controller

  plug :action

  def init(options) do
    options
  end

  def call(conn, opts) do
    conn = conn
    |> put_layout(opts[:layout])
    |> assign(:model, opts[:model])
    super(conn, action_name(conn))
  end

  def login(conn, %{"user" => %{"email" => email, "password" => password}}) do
    model = conn.assigns[:model]
    user = model.get(email: email)
    case model.auth?(user, password) do
      true ->
        user = Map.delete(user, :password)
        fetch_session(conn)
        |> put_session(:current_user, user)
        |> put_flash(:notice, "Innloggingen var vellykket")
        |> redirect(to: "/admin")
      false ->
        conn
        |> put_flash(:error, "Innloggingen feilet")
        |> redirect(to: "/login")
    end
  end

  def login(conn, _params) do
    conn
    |> render(:login)
  end

  def logout(conn, _params) do
    conn
    |> delete_session(:current_user)
    |> render(:logout)
  end
end
