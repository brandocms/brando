# Give the fresh Phoenix app application-owned code before running any installer.
File.mkdir_p!("assets/css")
File.write!("assets/css/legacy.css", "/* Existing consumer styles stay owned by the application. */\n")

File.write!(
  "test/legacy_test.exs",
  "defmodule IgniterSmoke.LegacyTest do\n use ExUnit.Case\n test \"existing test\", do: assert(true)\nend\n"
)

File.write!(
  "lib/igniter_smoke/catalog.ex",
  "defmodule IgniterSmoke.Catalog do\n # Keep this custom context function.\n def custom_marker, do: :preserved\nend\n"
)

File.write!("lib/igniter_smoke_web/controllers/health_controller.ex", """
defmodule IgniterSmokeWeb.HealthController do
  use IgniterSmokeWeb, :controller
  def show(conn, _), do: json(conn, %{status: "preserved"})
end
""")

application = File.read!("lib/igniter_smoke/application.ex")
true = String.contains?(application, "children = [")

replacement = "children = [\n      {Task.Supervisor, name: IgniterSmoke.LegacySupervisor},"
application = String.replace(application, "children = [", replacement, global: false)
File.write!("lib/igniter_smoke/application.ex", application)

router = File.read!("lib/igniter_smoke_web/router.ex")
route = ~s(get "/", PageController, :home)
true = String.contains?(router, route)

File.write!(
  "lib/igniter_smoke_web/router.ex",
  String.replace(router, route, ~s(get "/health-check", HealthController, :show\n    ) <> route, global: false)
)

File.write!("config/dev.exs", File.read!("config/dev.exs") <> "\nconfig :igniter_smoke, legacy_marker: :preserved\n")

paths = [
  "assets/css/legacy.css",
  "test/legacy_test.exs",
  "lib/igniter_smoke_web/controllers/health_controller.ex",
  "lib/igniter_smoke_web/controllers/page_html/home.html.heex"
]

hashes = Map.new(paths, &{&1, :crypto.hash(:sha256, File.read!(&1))})
File.write!(".igniter-smoke-customized", :erlang.term_to_binary(hashes))
