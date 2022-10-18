defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  If we have an authenticated user, we are allowed in.

  ## Example

  ```elixir
      plug Brando.Plug.Lockdown, [
        layout: {MyApp.LockdownLayoutView, "lockdown.html"},
        view: {MyApp.LockdownView, "lockdown.html"}
      ]
  ```

  ## Configure

      config :brando,
        lockdown: true,
        lockdown_password: "my_pass",
        lockdown_until: ~U[2040-01-13 13:00:00Z]

  `lockdown_password` and `lockdown_until` is optional. If no password
  configuration is found, you have to login through the backend to see
  the frontend website.

  You can also add a key as query string to set a cookie that allows browsing.

  `https://website/?key=<pass>`
  """
  alias Brando.Users
  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn, only: [halt: 1]

  @behaviour Plug

  def init(options), do: options

  def call(conn, _) do
    if Brando.config(:lockdown) do
      allowed?(conn, Brando.config(:lockdown_password))
    else
      conn
    end
  end

  defp allowed?(%{private: %{plug_session: %{"current_user" => user}}} = conn, _) do
    if Users.can_login?(user) do
      conn
    else
      lockdown(conn)
    end
  end

  defp allowed?(%{private: %{plug_session: %{"lockdown_authorized" => true}}} = conn, _), do: conn

  defp allowed?(%{query_params: %{"key" => key}} = conn, pass) when key == pass,
    do: Plug.Conn.put_session(conn, :lockdown_authorized, true)

  defp allowed?(conn, _), do: lockdown(conn)
  defp lockdown(conn), do: check_lockdown_date(conn, Brando.config(:lockdown_until))

  defp check_lockdown_date(conn, nil) do
    conn
    |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
    |> halt
  end

  defp check_lockdown_date(conn, lockdown_until) do
    if DateTime.compare(lockdown_until, DateTime.utc_now()) == :gt do
      conn
      |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
      |> halt
    else
      conn
    end
  end
end
