defmodule BrandoAdmin.UserSessionController do
  use BrandoAdmin, :controller

  alias Brando.Users
  alias BrandoAdmin.UserAuth

  def new(conn, _params) do
    conn
    |> put_root_layout(:auth)
    |> render(:new, error_message: nil)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    case Users.get_user(%{matches: %{email: email, active: true}}) do
      {:ok, user} ->
        if Bcrypt.verify_pass(password, user.password) do
          UserAuth.log_in_user(conn, user, user_params)
        else
          Bcrypt.no_user_verify()

          conn
          |> put_root_layout(:auth)
          |> render(:new, error_message: "Invalid email or password")
        end

      _ ->
        conn
        |> put_root_layout(:auth)
        |> render(:new, error_message: "Invalid email or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
