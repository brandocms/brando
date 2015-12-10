defmodule Brando.Admin.DashboardController do
  @moduledoc """
  A module for the admin dashboard.
  """

  use Brando.Web, :controller
  import Brando.Plug.HTML
  import Brando.Gettext

  @log_filename "supervisord.log"

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
    log_file = Path.join([Brando.config(:log_dir), @log_filename])
    {log_last_updated, log_last_lines} =
      case File.stat(log_file) do
        {:ok, stat} ->
          last_updated =
            stat.mtime
            |> Ecto.DateTime.from_erl
            |> Ecto.DateTime.to_string

          last_lines =
            log_file
            |> File.stream!
            |> Enum.reverse
            |> Enum.take(30)
            |> Enum.reverse

          {last_updated, last_lines}
        {:error, _} ->
          {"", gettext("File not found")}
      end

    conn
    |> assign(:log_last_lines, log_last_lines)
    |> assign(:log_last_updated, log_last_updated)
    |> render
  end
end
