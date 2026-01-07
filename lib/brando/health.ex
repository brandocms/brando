defmodule Brando.Health do
  @moduledoc """
  Health check logic for Brando applications.

  Provides system metrics and database connectivity checks.
  """

  @doc """
  Performs a full health check and returns a map with results.
  """
  @spec check() :: map()
  def check do
    db_check = check_database()
    system_metrics = get_system_metrics()

    overall_status = if db_check.status == "ok", do: "ok", else: "error"

    %{
      status: overall_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: %{
        database: db_check,
        system: system_metrics
      },
      version: Application.spec(:brando, :vsn) |> to_string()
    }
  end

  @doc """
  Checks if the connection originates from localhost.

  Handles:
  - IPv4 localhost: 127.0.0.1
  - IPv6 localhost: ::1
  - IPv4-mapped IPv6 localhost: ::ffff:127.0.0.1 (when IPv4 connects to IPv6 socket)
  """
  @spec localhost?(Plug.Conn.t()) :: boolean()
  def localhost?(conn) do
    case conn.remote_ip do
      # Native IPv4 localhost
      {127, 0, 0, 1} -> true
      # Native IPv6 localhost
      {0, 0, 0, 0, 0, 0, 0, 1} -> true
      # IPv4-mapped IPv6 localhost (::ffff:127.0.0.1)
      # 127.0.0.1 maps to: 127*256+0=32512, 0*256+1=1
      {0, 0, 0, 0, 0, 65535, 32512, 1} -> true
      _ -> false
    end
  end

  defp check_database do
    start = System.monotonic_time(:microsecond)

    try do
      case Brando.repo().query("SELECT 1", [], timeout: 5000) do
        {:ok, _} ->
          latency = (System.monotonic_time(:microsecond) - start) / 1000
          %{status: "ok", latency_ms: Float.round(latency, 2)}

        {:error, reason} ->
          %{status: "error", error: format_error(reason)}
      end
    rescue
      e ->
        %{status: "error", error: Exception.message(e)}
    end
  end

  defp get_system_metrics do
    memory = :erlang.memory()
    total_mb = memory[:total] / (1024 * 1024)

    %{
      memory_mb: Float.round(total_mb, 1),
      process_count: length(Process.list()),
      uptime_seconds: get_uptime()
    }
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
