defmodule Brando.LockdownController do
  use Brando.Web, :controller

  def index(conn, _) do
    conn
    |> put_layout({Brando.LayoutView, "lockdown.html"})
    |> render("index.html")
  end

  def post_password(conn, %{"password" => password}) do
    hashed_pass = Comeonin.Bcrypt.hashpwsalt(Brando.config(:lockdown_password))

    if Comeonin.Bcrypt.checkpw(password, hashed_pass) do
      conn
      |> fetch_session
      |> put_session(:lockdown_authorized, true)
      |> redirect(to: "/")
    else
      redirect conn, to: Brando.helpers().lockdown_path(conn, :index)
    end
  end
end
