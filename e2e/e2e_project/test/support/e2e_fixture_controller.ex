defmodule E2EFixtureController do
  use E2eProjectWeb, :controller

  def login(conn, %{"email" => email}) do
    user = Brando.Users.get_user!(%{matches: %{email: email}})

    conn
    |> login_user(user)
    |> send_resp(200, "")
  end

  def setup(conn, %{"name" => scenario_name}) do
    # Extract the metadata from the user agent
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [beam | _] ->
        # Allow this process to use the associated transaction
        Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    end

    # Build the scenario
    scenario =
      case scenario_name do
        "admin-user" -> get_admin_user()
      end

    # Log the user in
    conn
    |> login_user(scenario)
    |> send_resp(200, "")
  end

  def get_admin_user do
    Brando.Users.get_user!(%{matches: %{email: "admin@brandocms.com"}})
  end

  def login_user(conn, user) do
    token = Brando.Users.generate_user_session_token(user)

    conn
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.put_session(:user_token, token)
    |> Plug.Conn.put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end
end
