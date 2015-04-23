defmodule Brando.AuthController do
  @moduledoc """
  Controller for authentication actions.
  """
  use Brando.Web, :controller
  alias Brando.AdminChannel
  plug :action

  @doc false
  def login(conn, %{"user" => %{"email" => email, "password" => password}}) do
    model = conn.private[:model]
    user = model.get(email: email)
    case model.auth?(user, password) do
      true ->
        user = user
        |> model.set_last_login
        |> Map.delete(:password)

        AdminChannel.log(:logged_in, user)

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

  @doc false
  def login(conn, _params) do
    conn
    |> put_layout({Brando.Auth.LayoutView, "auth.html"})
    |> render(:login)
  end

  @doc false
  def logout(conn, _params) do
    if user = Brando.HTML.current_user(conn), do:
      AdminChannel.log(:logged_out, user)
    conn
    |> put_layout({Brando.Auth.LayoutView, "auth.html"})
    |> delete_session(:current_user)
    |> render(:logout)
  end
end
