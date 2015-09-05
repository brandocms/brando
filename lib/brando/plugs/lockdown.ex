defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  If we have an authenticated user, we are allowed in.

  ## Example

      plug Brando.Plug.Lockdown,
           [layout: {MyApp.LockdownLayoutView, "lockdown.html"},
            view: {MyApp.LockdownView, "lockdown.html"}]

  """

  import Phoenix.Controller, only: [put_flash: 3, redirect: 2,
                                    put_layout: 2, put_view: 2]
  import Plug.Conn, only: [halt: 1]
  alias Brando.User

  @behaviour Plug

  def init(options), do: options

  def call(conn, _) do
    if Brando.config(:lockdown) do
      conn |> allowed?
    else
      conn
    end
  end

  defp allowed?(%{private: %{plug_session: %{"current_user" => cu}}} = conn) do
    case User.can_login?(cu) do
      true  -> conn
      false -> conn |> lockdown
    end
  end

  defp allowed?(conn), do: conn |> lockdown

  defp lockdown(conn) do
    conn
    |> redirect(to: Brando.helpers.lockdown_path(conn, :index))
    |> halt
  end
end
