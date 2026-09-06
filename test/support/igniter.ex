defmodule Brando.IgniterCase do
  @moduledoc false

  def phoenix_project(options \\ []) do
    app = options[:app] || :studio
    module = options[:module] || "Studio"
    web = options[:web] || "#{module}Web"
    app_path = Atom.to_string(app)
    web_path = Macro.underscore(web)

    files = %{
      "mix.exs" => """
      defmodule #{module}.MixProject do
        use Mix.Project
        def project, do: [app: :#{app}, version: "0.1.0", deps: deps()]
        def application, do: [mod: {#{module}.Application, []}]
        defp deps, do: [{:brando, path: "../framework"}]
      end
      """,
      "lib/#{app_path}/application.ex" => """
      defmodule #{module}.Application do
        use Application
        def start(_type, _args), do: Supervisor.start_link([], strategy: :one_for_one)
      end
      """,
      "lib/#{app_path}/repo.ex" => """
      defmodule #{module}.Repo do
        use Ecto.Repo, otp_app: :#{app}, adapter: Ecto.Adapters.Postgres
      end
      """,
      "lib/#{web_path}.ex" => """
      defmodule #{web} do
        def router, do: quote(do: use(Phoenix.Router))
        defmacro __using__(which), do: apply(__MODULE__, which, [])
      end
      """,
      "lib/#{web_path}/router.ex" => """
      defmodule #{web}.Router do
        use #{web}, :router
        pipeline :browser do
          plug :accepts, ["html"]
          plug :fetch_session
        end
        scope "/", #{web} do
          pipe_through :browser
          get "/health", HealthController, :show
        end
      end
      """,
      "lib/#{web_path}/endpoint.ex" => """
      defmodule #{web}.Endpoint do
        use Phoenix.Endpoint, otp_app: :#{app}
        plug #{web}.Router
      end
      """,
      "assets/backend/package.json" => ~s({"dependencies":{"@brandocms/brandojs":"file:.yalc/@brandocms/brandojs"}}),
      "test/existing_test.exs" => "# Existing application tests must stay here.\n"
    }

    # Set up Igniter before supplying the consumer files: its setup formatter
    # evaluates config/config.exs, whereas source discovery must only read it.
    igniter = Igniter.Test.test_project(app_name: app)

    files =
      igniter.assigns.test_files
      |> Map.merge(files)
      |> Map.merge(options[:files] || %{})

    igniter = Igniter.assign(igniter, :test_files, files)
    Enum.reduce(Map.keys(files), igniter, &Igniter.include_existing_file(&2, &1))
  end

  def source(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end
end
