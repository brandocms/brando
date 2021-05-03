defmodule Brando.Plug.Authentication do
  use Plug.Router

  alias Brando.Users
  alias Plug.Conn

  plug :match
  plug :dispatch

  @doc false
  def call(conn, opts) do
    guardian_module = Keyword.fetch!(opts, :guardian_module)
    authorization_module = Keyword.fetch!(opts, :authorization_module)

    conn =
      conn
      |> Conn.put_private(:guardian_module, guardian_module)
      |> Conn.put_private(:authorization_module, authorization_module)

    super(conn, opts)
  end

  get "/login" do
    conn
    |> send_resp(200, "LOGIN :)")
  end

  post "/login" do
    authorization_module = conn.private.authorization_module

    with {:ok, email} <- Map.fetch(conn.body_params, "email"),
         {:ok, password} <- Map.fetch(conn.body_params, "password"),
         {:ok, user} <- Users.get_user(%{matches: %{email: email, active: true}}),
         {:verified, true} <- {:verified, Bcrypt.verify_pass(password, user.password)} do
      guardian_module = conn.private.guardian_module
      {:ok, jwt, _full_claims} = guardian_module.encode_and_sign(user)
      Users.set_last_login(user)

      payload = %{
        jwt: jwt,
        rules: authorization_module.get_rules_for(user.role),
        config: user.config,
        last_login: user.last_login
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(payload))
    else
      {:error, {:user, :not_found}} ->
        Bcrypt.no_user_verify()

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Feil ved innlogging"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Feil ved innlogging"}))
    end
  end

  post "/logout" do
    with {:ok, jwt} <- Map.fetch(conn.body_params, "jwt") do
      guardian_module = conn.private.guardian_module
      guardian_module.revoke(jwt)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{ok: true}))
    end
  end

  post "/verify" do
    guardian_module = conn.private.guardian_module
    authorization_module = conn.private.authorization_module

    with {:ok, jwt} <- Map.fetch(conn.body_params, "jwt"),
         {:ok, claims} <- guardian_module.decode_and_verify(jwt),
         {:ok, user} <- guardian_module.resource_from_claims(claims) do
      payload = %{
        ok: true,
        rules: authorization_module.get_rules_for(user.role)
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(payload))
    else
      {:error, :token_expired} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "expired"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "expired"}))
    end
  end
end
