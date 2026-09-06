if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Telemetry do
    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Config
    alias Igniter.Project.Deps
    alias Igniter.Project.MixProject
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Dependencies
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Project
    alias Mix.Brando.Igniter.Template

    @dependencies [
      {:opentelemetry_exporter, "~> 1.6"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_api, "~> 1.2"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_oban, "~> 1.0"}
    ]

    def plan(igniter) do
      with {:ok, igniter, options} <- Configuration.namespace_options(igniter, igniter.args.options),
           {:ok, igniter, project} <- Project.discover(igniter, options),
           {:ok, adapter} <- adapter(igniter, options),
           {:ok, exporter} <- exporter(options[:exporter] || "none") do
        igniter
        |> dependencies(adapter)
        |> wrapper(project)
        |> setup(project, adapter)
        |> configuration(project, options, exporter)
        |> release(project)
        |> Igniter.add_notice("""
        Review telemetry initialization and runtime configuration. Exporting defaults to :none.
        To export, select --exporter otlp on first generation or update the existing configuration,
        and supply OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS in the environment.
        No provider credentials or project-specific hostnames are generated.
        """)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp adapter(igniter, options) do
      case options[:adapter] do
        "bandit" -> {:ok, :bandit}
        "cowboy2" -> {:ok, :cowboy2}
        nil -> infer_adapter(igniter)
        _ -> {:error, "--adapter must be bandit or cowboy2."}
      end
    end

    defp infer_adapter(igniter) do
      case {Deps.has_dep?(igniter, :bandit), Deps.has_dep?(igniter, :plug_cowboy)} do
        {true, false} -> {:ok, :bandit}
        {false, true} -> {:ok, :cowboy2}
        _ -> {:error, "Select the Phoenix HTTP adapter with --adapter bandit or --adapter cowboy2."}
      end
    end

    defp exporter("none"), do: {:ok, :none}
    defp exporter("otlp"), do: {:ok, :otlp}
    defp exporter(_), do: {:error, "--exporter must be none or otlp."}

    defp dependencies(igniter, adapter) do
      dependency = if adapter == :bandit, do: {:opentelemetry_bandit, "~> 0.3.0"}, else: {:opentelemetry_cowboy, "~> 1.0"}

      Enum.reduce(@dependencies ++ [dependency], igniter, fn dependency, igniter ->
        Dependencies.add_new(igniter, dependency)
      end)
    end

    defp wrapper(igniter, project) do
      case Template.render(igniter, "brando.gen.otel", "open_telemetry_ecto.ex.eex",
             application_module: project.app_module
           ) do
        {:ok, igniter, contents} ->
          module = Module.concat(project.app_module, O11y.OpenTelemetryEcto)
          Files.create(igniter, "lib/#{Macro.underscore(module)}.ex", contents)

        {:error, message} ->
          Igniter.add_issue(igniter, message)
      end
    end

    defp setup(igniter, project, adapter) do
      server = if adapter == :bandit, do: OpentelemetryBandit, else: :opentelemetry_cowboy
      wrapper = Module.concat(project.app_module, O11y.OpenTelemetryEcto)

      calls = [
        {server, 0, "#{inspect(server)}.setup()"},
        {OpentelemetryPhoenix, 1, "OpentelemetryPhoenix.setup(adapter: #{inspect(adapter)})"},
        {wrapper, 1, "#{inspect(wrapper)}.setup(#{inspect(project.repo)}.config()[:telemetry_prefix])"},
        {OpentelemetryOban, 1, "OpentelemetryOban.setup(trace: [:jobs])"}
      ]

      ProjectModule.find_and_update_module!(igniter, project.application_module, fn zipper ->
        with {:ok, start} <- CodeFunction.move_to_def(zipper, :start, 2, target: :at),
             {:ok, body} <- Common.move_to_do_block(start),
             :ok <- check_legacy_setup(body) do
          calls |> Enum.reverse() |> Enum.reduce_while({:ok, body}, &ensure_setup/2)
        else
          {:error, message} ->
            {:error, message}

          _ ->
            {:error,
             "Expected #{inspect(project.application_module)}.start/2 with a do block for telemetry initialization."}
        end
      end)
    end

    defp check_legacy_setup(body) do
      legacy = [{Brando.O11y.OpenTelemetryEcto, 1}, {OpentelemetryLiveView, 0}]

      if Enum.any?(legacy, fn {module, arity} ->
           match?({:ok, _}, CodeFunction.move_to_function_call_in_current_scope(body, {module, :setup}, arity))
         end) do
        {:error,
         "Review legacy telemetry initialization first: use your application-namespaced Ecto wrapper and remove duplicate OpentelemetryLiveView.setup/0 (Phoenix instrumentation now includes LiveView)."}
      else
        :ok
      end
    end

    defp ensure_setup({module, arity, code}, {:ok, body}) do
      case CodeFunction.move_to_function_call_in_current_scope(body, {module, :setup}, arity) do
        {:ok, call} when module == OpentelemetryPhoenix ->
          {{:., _, _}, _, [options]} = Code.string_to_quoted!(code)

          {:ok, argument} = CodeFunction.move_to_nth_argument(call, 0)

          if Common.expand_literal(argument) == {:ok, options} do
            {:cont, {:ok, body}}
          else
            {:halt,
             {:error,
              "Existing OpentelemetryPhoenix.setup options differ. Review the selected --adapter and preserve your intended instrumentation options explicitly."}}
          end

        {:ok, _call} ->
          {:cont, {:ok, body}}

        :error ->
          {:cont, {:ok, Common.add_code(body, code, placement: :before)}}
      end
    end

    defp configuration(igniter, project, options, exporter) do
      igniter
      |> Config.configure_new(
        "runtime.exs",
        :opentelemetry,
        [:resource, :service, :name],
        options[:service_name] || to_string(project.otp_app)
      )
      |> Config.configure_new(
        "runtime.exs",
        :opentelemetry,
        [:resource, :service, :namespace],
        inspect(project.app_module)
      )
      |> Config.configure_new("runtime.exs", :opentelemetry, [:span_processor], :batch)
      |> Config.configure_new("runtime.exs", :opentelemetry, [:traces_exporter], exporter)
      |> Config.configure_new("runtime.exs", :opentelemetry_exporter, [:otlp_protocol], :http_protobuf)
    end

    defp release(igniter, project) do
      Enum.reduce([opentelemetry_exporter: :permanent, opentelemetry: :temporary], igniter, fn {app, mode}, igniter ->
        MixProject.update(igniter, :project, [:releases, project.otp_app, :applications, app], fn
          nil -> {:ok, {:code, mode}}
          zipper -> {:ok, zipper}
        end)
      end)
    end
  end
end
