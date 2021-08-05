defmodule BrandoAdmin.UserSessionController do
  use BrandoAdmin, :controller

  alias Brando.Users
  alias BrandoAdmin.UserAuth

  def new(conn, _params) do
    conn
    |> put_root_layout(false)
    |> render("new.html", error_message: nil)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => _password} = user_params}) do
    with {:ok, user} <- Users.get_user(%{matches: %{email: email, active: true}}) do
      UserAuth.log_in_user(conn, user, user_params)
    else
      _ -> render(conn, "new.html", error_message: "Invalid email or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
