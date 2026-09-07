defmodule Mix.Brando.Igniter.TelemetryTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase

  test "uses consumer identity and Repo config and boots without provider secrets" do
    result =
      IgniterCase.phoenix_project(app: :shop, module: "Acme.Shop", web: "Acme.Web")
      |> Igniter.compose_task("brando.gen.otel", ["--adapter", "bandit"])

    assert result.issues == []
    application = IgniterCase.source(result, "lib/shop/application.ex")
    assert application =~ "Acme.Shop.O11y.OpenTelemetryEcto.setup(Acme.Shop.Repo.config()[:telemetry_prefix])"
    assert application =~ "OpentelemetryPhoenix.setup(adapter: :bandit)"
    assert application =~ "OpentelemetryBandit.setup()"
    refute application =~ "Brando.O11y"
    refute application =~ "OpentelemetryLiveView.setup()"
    config = IgniterCase.source(result, "config/runtime.exs")
    assert config =~ ~s(name: "shop")
    assert config =~ ~s(namespace: "Acme.Shop")
    assert config =~ "traces_exporter: :none"
    refute config =~ "fetch_env!"
    refute config =~ "BielkeYang"
    assert result.tasks == [{"deps.get", []}]

    result = IgniterCase.apply_and_reload(result)
    rerun = Igniter.compose_task(result, "brando.gen.otel", ["--adapter", "bandit"])
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "adds initial OTLP choices but keeps an existing service, exporter and release setting" do
    result =
      IgniterCase.phoenix_project(
        files: %{
          "config/runtime.exs" =>
            "import Config\nconfig :opentelemetry, resource: [service: [name: \"existing\"]], traces_exporter: :none\n"
        }
      )
      |> Igniter.compose_task("brando.gen.otel", [
        "--adapter",
        "cowboy2",
        "--exporter",
        "otlp",
        "--service-name",
        "proposed"
      ])

    assert result.issues == []
    config = IgniterCase.source(result, "config/runtime.exs")
    assert config =~ ~s(name: "existing")
    assert config =~ "traces_exporter: :none"
    assert IgniterCase.source(result, "lib/studio/application.ex") =~ ":opentelemetry_cowboy.setup()"
    refute IgniterCase.source(result, "mix.exs") =~ "opentelemetry_bandit"
  end

  test "customized wrappers are preserved and require review" do
    path = "lib/studio/o11y/open_telemetry_ecto.ex"

    result =
      IgniterCase.phoenix_project(
        files: %{path => "defmodule Studio.O11y.OpenTelemetryEcto do\n def custom, do: true\nend"}
      )
      |> Igniter.compose_task("brando.gen.otel", ["--adapter", "bandit", "--yes"])

    assert Enum.any?(result.issues, &String.contains?(&1, "different content"))
    Igniter.Test.assert_unchanged(result, path)
  end

  test "missing or invalid adapter and exporter fail before source changes" do
    for args <- [[], ["--adapter", "unknown"], ["--adapter", "bandit", "--exporter", "unknown"]] do
      result = IgniterCase.phoenix_project() |> Igniter.compose_task("brando.gen.otel", args)
      assert result.issues != []
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "legacy or conflicting instrumentation requires review instead of double registration" do
    for setup <- [
          "Brando.O11y.OpenTelemetryEcto.setup([:by, :repo])",
          "OpentelemetryLiveView.setup()",
          "OpentelemetryPhoenix.setup(adapter: :cowboy2)"
        ] do
      project = IgniterCase.phoenix_project()

      project =
        Igniter.update_file(project, "lib/studio/application.ex", fn source ->
          Rewrite.Source.update(
            source,
            :content,
            String.replace(Rewrite.Source.get(source, :content), "children =", "#{setup}\n    children =")
          )
        end)

      project = IgniterCase.apply_and_reload(project)
      result = Igniter.compose_task(project, "brando.gen.otel", ["--adapter", "bandit"])
      assert result.issues != []
      Igniter.Test.assert_unchanged(result, "lib/studio/application.ex")
    end
  end
end
