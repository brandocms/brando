defmodule Brando.SessionController do
  use Brando.Web, :controller
  alias Brando.User

  def create(conn, %{"email" => email, "password" => password}) do
    case Brando.repo.get_by(User, email: email) do
      nil ->
        Comeonin.Bcrypt.dummy_checkpw()

        conn
        |> put_status(:unauthorized)
        |> render("error.json")

      user ->
        if Comeonin.Bcrypt.checkpw(password, user.password) do
            # |> Utils.add_avatar(:medium)

          {:ok, jwt, _full_claims} = Guardian.encode_and_sign(user, :token)

          conn
          |> put_status(:created)
          |> render("show.json", jwt: jwt, user: user)
        else
          conn
          |> put_status(:unauthorized)
          |> render("error.json")
        end
    end
  end

  def delete(conn, %{"jwt" => jwt}) do
    Guardian.revoke!(jwt)

    render(conn, "delete.json")
  end

  def verify(conn, %{"jwt" => jwt}) do
    case Guardian.decode_and_verify(jwt) do
      {:error, :token_expired} ->
        conn
        |> put_status(:unauthorized)
        |> render("expired.json")
      _ ->
        conn
        |> put_status(:ok)
        |> render("ok.json")
    end
  end
end
