defmodule Brando.Dashboard.Admin.DashboardController do
  @moduledoc """
  A module for the admin dashboard.
  """

  use Phoenix.Controller
  plug :action

  @doc """
  Renders the main dashboard for the admin area.
  """
  def dashboard(conn, _params) do
    conn |> render
  end

end

