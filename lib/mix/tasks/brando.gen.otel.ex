if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Otel do
    use Igniter.Mix.Task

    @shortdoc "Plans application-scoped OpenTelemetry instrumentation"
    @moduledoc """
    Instruments the selected Phoenix adapter, LiveView, Repo and Oban:

        mix brando.gen.otel
        mix brando.gen.otel --adapter bandit --exporter otlp

    Infers a single Bandit/PlugCowboy dependency or requires --adapter. Service
    identity defaults to the discovered OTP application and module namespace;
    --service-name overrides the proposed name. Existing configuration is preserved.
    Exporting defaults to none. For OTLP, configure the standard
    OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS environment variables.
    No Honeycomb-specific credentials are required to boot.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        schema:
          Mix.Brando.Igniter.Project.options() ++
            [adapter: :string, exporter: :string, service_name: :string]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Telemetry.plan(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Otel do
    use Mix.Task
    @shortdoc "Plans OpenTelemetry instrumentation (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.otel")
  end
end
