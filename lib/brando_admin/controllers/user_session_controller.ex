defmodule BrandoAdmin.UserSessionController do
  use BrandoAdmin, :controller
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias BrandoAdmin.UserAuth

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    case Users.get_user(%{matches: %{email: email, active: true}}) do
      {:ok, user} ->
        if Bcrypt.verify_pass(password, user.password) do
          UserAuth.log_in_user(conn, user, user_params)
        else
          Bcrypt.no_user_verify()

          conn
          |> put_flash(:error, gettext("Invalid email or password"))
          |> put_flash(:email, String.slice(email, 0, 160))
          |> redirect(to: "/admin/login")
        end

      _ ->
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: "/admin/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
