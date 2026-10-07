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
          invalid(conn, email)
        end

      _ ->
        # Takes as long as checking a password, so the time taken does not
        # tell whether the account exists.
        Bcrypt.no_user_verify()
        invalid(conn, email)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end

  defp invalid(conn, email) do
    conn
    |> put_flash(:error, gettext("Invalid email or password"))
    |> put_flash(:email, String.slice(email, 0, 160))
    |> redirect(to: "/admin/login")
  end
end
