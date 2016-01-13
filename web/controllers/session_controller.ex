defmodule Brando.SessionController do
  @moduledoc """
  Controller for authentication actions.
  """

  use Brando.Web, :controller
  alias Brando.SystemChannel
  import Brando.Gettext

  @doc false
  def login(conn, %{"user" => %{"email" => email, "password" => password}}) do
    model = conn.private[:model]
    user = Brando.repo.get_by(model, email: email)
    case model.auth?(user, password) do
      true ->
        user =
          user
          |> model.set_last_login
          |> sanitize_user

        SystemChannel.log(:logged_in, user)

        conn
        |> sleep
        |> fetch_session
        |> put_session(:current_user, user)
        |> redirect(to: "/admin")
      false ->
        conn
        |> sleep
        |> put_flash(:error, gettext("Authorization failed"))
        |> redirect(to: "/auth/login")
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
    user = Brando.Utils.current_user(conn)
    if user do
      SystemChannel.log(:logged_out, user)
    end

    conn
    |> put_layout({Brando.Session.LayoutView, "auth.html"})
    |> delete_session(:current_user)
    |> render(:logout)
  end

  defp sanitize_user(user) do
    Map.drop(user, [:password, :__meta__])
  end

  defp sleep(conn) do
    :timer.sleep(Brando.config(:auth_sleep_duration))
    conn
  end
end
