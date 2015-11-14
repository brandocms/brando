defmodule Brando.Admin.DashboardController do
  @moduledoc """
  A module for the admin dashboard.
  """

  use Brando.Web, :controller
  import Brando.Plug.HTML
  import Brando.Gettext

  plug :put_section, "dashboard"

  @doc """
  Renders the main dashboard for the admin area.
  """
  def dashboard(conn, _params) do
    render(conn)
  end

  @doc """
  Renders system info page.
  """
  def system_info(conn, _params) do
    log_file = "#{Path.expand("./logs")}/supervisord.log"
    case File.stat(log_file) do
      {:ok, stat} ->
        log_last_updated =
          stat.mtime
          |> Ecto.DateTime.from_erl
          |> Ecto.DateTime.to_string

        log_last_lines =
          log_file
          |> File.stream!
          |> Enum.reverse
          |> Enum.take(30)
          |> Enum.reverse
      {:error, _} ->
        log_last_updated = ""
        log_last_lines = gettext("File not found")
    end

    conn
    |> assign(:log_last_lines, log_last_lines)
    |> assign(:log_last_updated, log_last_updated)
    |> render
  end

  def instagram_start(conn, _) do
    Brando.Instagram.Server.start_link()
    redirect(conn, to: Brando.helpers.admin_dashboard_path(conn, :system_info))
  end
end
