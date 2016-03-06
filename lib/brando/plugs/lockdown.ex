defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  If we have an authenticated user, we are allowed in.

  ## Example

      plug Brando.Plug.Lockdown,
           [layout: {MyApp.LockdownLayoutView, "lockdown.html"},
            view: {MyApp.LockdownView, "lockdown.html"}]

  """
  alias Brando.User
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2,
                                    put_layout: 2, put_view: 2]
  import Plug.Conn, only: [halt: 1]

  @behaviour Plug

  def init(options), do: options

  def call(conn, _) do
    if Brando.config(:lockdown) do
      allowed?(conn)
    else
      conn
    end
  end

  defp allowed?(%{private: %{plug_session: %{"current_user" => user}}} = conn) do
    case User.can_login?(user) do
      true  -> conn
      false -> lockdown(conn)
    end
  end

  defp allowed?(%{private: %{plug_session: %{"lockdown_authorized" => true}}} = conn) do
    conn
  end

  defp allowed?(conn), do: lockdown(conn)

  defp lockdown(conn) do
    conn
    |> redirect(to: Brando.helpers.lockdown_path(conn, :index))
    |> halt
  end
end
