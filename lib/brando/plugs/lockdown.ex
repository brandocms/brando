defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  If we have an authenticated user, we are allowed in.

  ## Example

      plug Brando.Plug.Lockdown, [layout: {Neva.LockdownLayoutView, "lockdown.html"},
                                  view: {Neva.LockdownView, "lockdown.html"}]

  """

  import Phoenix.Controller, only: [put_flash: 3, redirect: 2, put_layout: 2, put_view: 2]
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

  defp allowed?(%{private: %{plug_session: %{"current_user" => current_user}}} = conn) do
    case User.can_login?(current_user) do
      true  -> conn
      false -> conn |> lockdown
    end
  end

  defp allowed?(conn), do: conn |> lockdown

  defp lockdown(conn) do
    conn
    |> redirect(to: Brando.get_helpers.lockdown_path(conn, :index))
  end
end