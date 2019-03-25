defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  If we have an authenticated user, we are allowed in.

  ## Example

      plug Brando.Plug.Lockdown

  The `Lockdown` plug looks for a `lockdown_path` in your `router.ex`.

  ## Example

      scope "/coming-soon" do
        get "/", Brando.LockdownController, :index
        post "/", Brando.LockdownController, :post_password
      end

  ## Configure

      config :brando,
        lockdown: true,
        lockdown_password: "my_pass",
        lockdown_until: ~N[2015-01-13 13:00:07]

  Password is optional. If no password configuration is found, you have to login
  through the backend to see the frontend website.

  """
  alias Brando.User
  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn, only: [halt: 1]

  @behaviour Plug

  @spec init(Keyword.t()) :: Keyword.t()
  def init(options), do: options

  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, _) do
    if Brando.config(:lockdown) do
      allowed?(conn, Brando.config(:lockdown_password))
    else
      conn
    end
  end

  @spec allowed?(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp allowed?(%{private: %{plug_session: %{"current_user" => user}}} = conn, _) do
    if User.can_login?(user) do
      conn
    else
      lockdown(conn)
    end
  end

  defp allowed?(%{private: %{plug_session: %{"lockdown_authorized" => true}}} = conn, _), do: conn

  defp allowed?(%{query_params: %{"key" => key}} = conn, pass) when key == pass,
    do: Plug.Conn.put_session(conn, :lockdown_authorized, true)

  defp allowed?(conn, _), do: lockdown(conn)

  @spec lockdown(Plug.Conn.t()) :: Plug.Conn.t()
  defp lockdown(conn) do
    check_lockdown_date(conn, Brando.config(:lockdown_until))
  end

  defp check_lockdown_date(conn, nil) do
    conn
    |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
    |> halt
  end

  defp check_lockdown_date(conn, lockdown_until) do
    lockdown_until = Timex.to_datetime(lockdown_until, "Europe/Oslo")
    time_now = Timex.now("Europe/Oslo")

    if DateTime.compare(lockdown_until, time_now) == :gt do
      conn
      |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
      |> halt
    else
      conn
    end
  end
end
