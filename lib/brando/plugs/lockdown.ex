defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  While locked, visitors are redirected to `lockdown_path(conn, :index)`,
  which `mix brando.gen.site` routes to `YourWeb.CMS.LockdownController` at
  `/coming-soon`. Users signed in to the admin, the admin's live preview and
  visitors who have entered the password are let through.

  ## Example

  ```elixir
      plug Brando.Plug.Lockdown
  ```

  The plug needs the session fetched, so it goes in a pipeline after
  `:browser`. `mix brando.gen.site` puts it in the `:brando_site` pipeline.

  ## Configure

      config :brando,
        lockdown: true,
        lockdown_password: "my_pass",
        lockdown_until: ~U[2040-01-13 13:00:00Z]

  `lockdown_password` and `lockdown_until` are optional. Without a password,
  only users signed in to the admin see the site. Past `lockdown_until`, the
  site is open.

  You can also add the password as a query string to set a cookie that allows browsing.

  `https://website/?key=<pass>`
  """
  @behaviour Plug

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn, only: [halt: 1]

  alias Brando.Users

  def init(options), do: options

  def call(conn, _) do
    if Brando.config(:lockdown) do
      allowed?(conn, Brando.config(:lockdown_password))
    else
      conn
    end
  end

  defp allowed?(%{private: %{brando_live_preview: true}} = conn, _), do: conn

  defp allowed?(conn, pass) do
    session = conn.private[:plug_session] || %{}

    cond do
      signed_in?(session["user_token"]) ->
        conn

      session["lockdown_authorized"] == true ->
        conn

      is_binary(pass) and match?(%{"key" => ^pass}, conn.query_params) ->
        Plug.Conn.put_session(conn, :lockdown_authorized, true)

      true ->
        lockdown(conn)
    end
  end

  # The session the admin's sign-in writes (BrandoAdmin.UserAuth).
  defp signed_in?(token) when is_binary(token) do
    case Users.get_user_by_session_token(token) do
      nil -> false
      user -> Users.can_login?(user)
    end
  end

  defp signed_in?(_token), do: false
  defp lockdown(conn), do: check_lockdown_date(conn, Brando.config(:lockdown_until))

  defp check_lockdown_date(conn, nil) do
    conn
    |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
    |> halt()
  end

  defp check_lockdown_date(conn, lockdown_until) do
    if DateTime.after?(lockdown_until, DateTime.utc_now()) do
      conn
      |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
      |> halt()
    else
      conn
    end
  end
end
