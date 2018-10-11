defmodule <%= application_module %>Web.SessionController do
  @moduledoc """
  Generated session controller
  """
  use <%= application_module %>Web, :controller
  alias Brando.User
  alias <%= application_module %>.Repo

  @doc """
  Create new token
  """
  def create(conn, %{"email" => email, "password" => password}) do
    case Repo.get_by(User, email: email) do
      nil ->
        Comeonin.Bcrypt.dummy_checkpw()

        conn
        |> put_status(:unauthorized)
        |> render("error.json")

      user ->
        if Comeonin.Bcrypt.checkpw(password, user.password) do
          {:ok, jwt, _full_claims} = <%= application_module %>Web.Guardian.encode_and_sign(user)

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

  @doc """
  Delete token
  """
  def delete(conn, %{"jwt" => jwt}) do
    <%= application_module %>Web.Guardian.revoke(jwt)

    render(conn, "delete.json")
  end

  @doc """
  Verify token
  """
  def verify(conn, %{"jwt" => jwt}) do
    case <%= application_module %>Web.Guardian.decode_and_verify(jwt) do
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
