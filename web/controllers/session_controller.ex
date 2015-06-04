defmodule Brando.SessionController do
  @moduledoc """
  Controller for authentication actions.
  """
  use Brando.Web, :controller
  alias Brando.SystemChannel
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

        SystemChannel.log(:logged_in, user)

        conn
        |> fetch_session
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
    |> put_layout({Brando.Session.LayoutView, "auth.html"})
    |> render(:login)
  end

  @doc false
  def logout(conn, _params) do
    if user = Brando.HTML.current_user(conn), do:
      SystemChannel.log(:logged_out, user)
    conn
    |> put_layout({Brando.Session.LayoutView, "auth.html"})
    |> delete_session(:current_user)
    |> render(:logout)
  end
end
