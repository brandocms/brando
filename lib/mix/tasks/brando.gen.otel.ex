if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Otel do
    use Igniter.Mix.Task

    @shortdoc "Generates otel/honeycomb setup"
    @moduledoc """
    #{@shortdoc}
    """

    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando}
    end

    def igniter(igniter) do
      igniter
      |> add_dependencies()
      |> add_runtime_cfg()
      |> copy_o11y_ecto()
      |> add_setup_to_application()
      |> add_to_mix()
    end

    defp copy_o11y_ecto(igniter) do
      src_file =
        :brando
        |> Application.app_dir(["priv", "templates", "brando.gen.otel"])
        |> Path.join("open_telemetry_ecto.ex.eex")

      module_name = Igniter.Project.Module.module_name(igniter, "O11y.OpenTelemetryEcto")
      dest_file = Igniter.Project.Module.proper_location(igniter, module_name)

      Igniter.copy_template(
        igniter,
        src_file,
        dest_file,
        application_module: Igniter.Project.Module.module_name_prefix(igniter),
        on_exists: :overwrite
      )
    end

    defp add_dependencies(igniter) do
      igniter
      |> Igniter.Project.Deps.add_dep({:opentelemetry_exporter, "~> 1.6"}, append?: true)
      |> Igniter.Project.Deps.add_dep({:opentelemetry, "~> 1.3"}, append?: true)
      |> Igniter.Project.Deps.add_dep({:opentelemetry_api, "~> 1.2"}, append?: true)
      |> Igniter.Project.Deps.add_dep({:opentelemetry_phoenix, "~> 2.0.0-rc.1"}, append?: true)
      |> Igniter.Project.Deps.add_dep({:opentelemetry_bandit, "~> 0.2.0-rc.1"}, append?: true)
      |> Igniter.Project.Deps.add_dep({:opentelemetry_ecto, "~> 1.2"}, append?: true)
      |> Igniter.Project.Deps.add_dep({:opentelemetry_liveview, "~> 1.0.0-rc.4"}, append?: true)
      |> Igniter.Project.Deps.add_dep({:opentelemetry_telemetry, "~> 1.1.2", [override: true]},
        append?: true
      )
      |> Igniter.Project.Deps.add_dep({:opentelemetry_oban, "~> 1.0"}, append?: true)
    end

    defp add_runtime_cfg(igniter) do
      igniter
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :opentelemetry,
        [:resource],
        {:code,
         Sourceror.parse_string!("""
         [service: [
             name: "by",
             namespace: "BielkeYang"
           ],
           host: [
             name: "localdev"
         ]]
         """)}
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :opentelemetry,
        [:span_processor],
        :batch
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :opentelemetry,
        [:traces_exporter],
        :otlp
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :opentelemetry_exporter,
        [:otlp_protocol],
        :http_protobuf
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :opentelemetry_exporter,
        [:otlp_endpoint],
        "https://api.honeycomb.io:443"
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :opentelemetry_exporter,
        [:otlp_headers],
        {:code,
         Sourceror.parse_string!("""
         [{"x-honeycomb-team", System.fetch_env!("HONEYCOMB_API_KEY")}, {"x-honeycomb-dataset", "dev"}]
         """)}
      )
    end

    defp add_setup_to_application(igniter) do
      {app_module, _} = Igniter.Project.Application.app_module(igniter)

      Igniter.Project.Module.find_and_update_module!(igniter, app_module, fn zipper ->
        case Igniter.Code.Function.move_to_def(zipper, :start, 2) do
          {:ok, zipper} ->
            zipper =
              Igniter.Code.Common.add_code(
                zipper,
                """
                OpentelemetryBandit.setup()
                OpentelemetryPhoenix.setup(adapter: :bandit)
                Brando.O11y.OpenTelemetryEcto.setup([:by, :repo])
                OpentelemetryLiveView.setup()
                OpentelemetryOban.setup(trace: [:jobs])
                """,
                :before
              )

            {:ok, zipper}
        end
      end)
    end

    defp add_to_mix(igniter) do
      app_atom = Igniter.Project.Application.app_name(igniter)

      Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
        with {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :project, 0),
             {:ok, zipper} <-
               Igniter.Code.Keyword.put_in_keyword(
                 zipper,
                 [:releases, app_atom, :applications, :opentelemetry_exporter],
                 :permanent
               ) do
          Igniter.Code.Keyword.put_in_keyword(
            zipper,
            [:releases, app_atom, :applications, :opentelemetry],
            :temporary
          )
        end
      end)
    end
  end
end
