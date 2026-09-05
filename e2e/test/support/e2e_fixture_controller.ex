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

  # Only routed in the sandbox application. Browser tests use the real editor
  # for capture/restore; this injects failures that an editor cannot create.
  def drafts(conn, %{"action" => action}) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    user = get_admin_user()
    identity = Brando.Drafts.identity(Brando.Pages.Page, nil, user.id)
    [draft | _] = Brando.Drafts.list(identity)

    case action do
      "unsupported" ->
        draft |> Ecto.Changeset.change(format_version: 999) |> Brando.Repo.update!()

      "change-module" ->
        [row | _] = draft.payload["blocks"]["blocks"]
        {:ok, _} = Brando.Content.update_module(row["block"]["module_id"], %{refs: [], vars: []}, user)
    end

    json(conn, %{ok: true})
  end

  def login_user(conn, user) do
    token = Brando.Users.generate_user_session_token(user)

    conn
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.put_session(:user_token, token)
    |> Plug.Conn.put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end
end
