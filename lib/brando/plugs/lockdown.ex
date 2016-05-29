defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  If we have an authenticated user, we are allowed in.

  ## Example

      plug Brando.Plug.Lockdown, [
        layout: {MyApp.LockdownLayoutView, "lockdown.html"},
        view: {MyApp.LockdownView, "lockdown.html"}
      ]

  ## Configure

      config :brando,
        lockdown: true,
        lockdown_password: "my_pass"

  Password is optional. If no password configuration is found, you have to login
  through the backend to see the frontend website.

  """
  alias Brando.User
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2, put_layout: 2, put_view: 2]
  import Plug.Conn, only: [halt: 1]

  @behaviour Plug

  @spec init(Keyword.t) :: Keyword.t
  def init(options), do: options

  @spec call(Plug.Conn.t, Keyword.t) :: Plug.Conn.t
  def call(conn, _) do
    if Brando.config(:lockdown) do
      conn
      |> allowed?
    else
      conn
    end
  end

  @spec allowed?(Plug.Conn.t) :: Plug.Conn.t
  defp allowed?(%{private: %{plug_session: %{"current_user" => user}}} = conn) do
    if User.can_login?(user) do
      conn
    else
      lockdown(conn)
    end
  end

  defp allowed?(%{private: %{plug_session: %{"lockdown_authorized" => true}}} = conn), do: conn
  defp allowed?(conn), do: lockdown(conn)

  @spec lockdown(Plug.Conn.t) :: Plug.Conn.t
  defp lockdown(conn) do
    conn
    |> redirect(to: Brando.helpers.lockdown_path(conn, :index))
    |> halt
  end
end
