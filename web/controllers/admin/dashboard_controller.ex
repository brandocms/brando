defmodule Brando.Admin.DashboardController do
  @moduledoc """
  A module for the admin dashboard.
  """

  use Brando.Web, :controller
  import Brando.Plug.Section

  plug :put_section, "dashboard"

  @doc """
  Renders the main dashboard for the admin area.
  """
  def dashboard(conn, _params) do
    conn |> render
  end

  @doc """
  Renders system info page.
  """
  def system_info(conn, _params) do
    conn |> render
  end

end

