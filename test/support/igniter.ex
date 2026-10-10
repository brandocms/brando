defmodule Brando.IgniterCase do
  @moduledoc false

  # Igniter projects live in memory, but formatting a planned file is not
  # free of global state: `Igniter.format/2` evaluates the project's
  # config/config.exs and config/test.exs, puts every app they configure into
  # the application environment and restores it afterwards. A test whose
  # project configures `:brando` changes Brando's environment under concurrent
  # tests, so it must be `async: false`. Projects that configure only their own
  # app and `:swoosh` (which every install does) can be async in the
  # `:igniter_config` group: two of them formatting at once could restore each
  # other's snapshot and leave the change behind.

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
        def start(_type, _args) do
          children = [#{module}.Repo, {Phoenix.PubSub, name: #{module}.PubSub}, #{web}.Endpoint]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """,
      "lib/#{app_path}/repo.ex" => """
      defmodule #{module}.Repo do
        use Ecto.Repo, otp_app: :#{app}, adapter: Ecto.Adapters.Postgres
      end
      """,
      "lib/#{web_path}.ex" => """
      defmodule #{web} do
        def router, do: quote(do: use(Phoenix.Router, helpers: false))
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
        @session_options [store: :cookie, key: "_#{app}_key", signing_salt: "preserve-this-salt"]
        socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
        plug Plug.Static, at: "/", from: :#{app}, only: ~w(assets)
        plug Plug.Session, @session_options
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

    # Igniter may already have loaded its base project into Rewrite. Reload
    # these paths from the consumer fixture instead of retaining cached source.
    igniter =
      igniter
      |> Igniter.assign(:test_files, files)
      |> Map.update!(:rewrite, &Rewrite.drop(&1, Map.keys(files)))

    Enum.reduce(Map.keys(files), igniter, fn path, igniter ->
      options = if String.starts_with?(path, "priv/templates/"), do: [source_handler: Rewrite.Source], else: []
      Igniter.include_existing_file(igniter, path, options)
    end)
  end

  # A Phoenix project with the config, assets and Gettext a Brando install starts from.
  def install_project(files \\ %{}) do
    phoenix_project(
      files:
        Map.merge(
          %{
            "config/config.exs" => """
            import Config
            config :studio, StudioWeb.Endpoint, secret_key_base: "existing-secret", live_view: [signing_salt: "existing-lv-salt"]
            import_config "dev.exs"
            """,
            "config/dev.exs" => "import Config\n",
            "assets/css/app.css" => "/* Existing Phoenix assets */",
            "lib/studio_web/gettext.ex" => "defmodule StudioWeb.Gettext do\n use Gettext.Backend, otp_app: :studio\nend\n"
          },
          files
        )
    )
  end

  def source(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  def apply_and_reload(igniter) do
    igniter = Igniter.Test.apply_igniter!(igniter)

    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, fn path, igniter ->
      options = if String.starts_with?(path, "priv/templates/"), do: [source_handler: Rewrite.Source], else: []
      Igniter.include_existing_file(igniter, path, options)
    end)
  end
end
