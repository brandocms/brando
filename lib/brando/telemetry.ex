defmodule Brando.Telemetry do
  @moduledoc """
  Telemetry handlers for Brando applications.

  Attaches handlers for error logging and other observability features.
  """

  require Logger

  @doc """
  Attaches telemetry handlers. Called automatically from Brando.Supervisor.
  """
  def attach do
    :telemetry.attach(
      "brando-error-logger",
      [:phoenix, :error_rendered],
      &__MODULE__.handle_error_rendered/4,
      :no_config
    )

    :ok
  end

  @doc false
  def handle_error_rendered(_event, _measurements, metadata, _config) do
    case metadata do
      %{reason: reason, stacktrace: stacktrace} when is_exception(reason) ->
        Logger.error("""
        Exception rendered as HTTP error:
        #{Exception.format(:error, reason, stacktrace)}
        """)

      %{reason: reason} when is_exception(reason) ->
        Logger.error("Exception rendered as HTTP error: #{Exception.message(reason)}")

      _ ->
        :ok
    end
  end
end
