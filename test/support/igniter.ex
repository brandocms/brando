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
      |> Map.drop(options[:without] || [])

    # Igniter may already have loaded its base project into Rewrite. Reload
    # these paths from the consumer fixture instead of retaining cached source.
    igniter =
      igniter
      |> Igniter.assign(:test_files, files)
      |> Map.update!(:rewrite, &Rewrite.drop(&1, Map.keys(files)))

    include_files(igniter, files)
  end

  def source(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  def apply_and_reload(igniter) do
    igniter = Igniter.Test.apply_igniter!(igniter)
    files = igniter.assigns.test_files

    # Igniter.Test re-includes every file before it applies moves, so a moved
    # file stays in the rewrite under its old path. Its glob skips dot
    # directories in the checkout's absolute path, so this only shows where
    # there are none, as in CI.
    moved_away = for source <- Rewrite.sources(igniter.rewrite), not Map.has_key?(files, source.path), do: source.path
    igniter = %{igniter | rewrite: Rewrite.drop(igniter.rewrite, moved_away)}

    include_files(igniter, files)
  end

  # Not the consumer's generator templates, which a task reads when it uses
  # them, as from disk: Igniter parses each `.ex` source it writes, and an EEx
  # template named `.ex` does not parse.
  defp include_files(igniter, files) do
    files
    |> Map.keys()
    |> Enum.reject(&String.starts_with?(&1, "priv/templates/"))
    |> Enum.reduce(igniter, &Igniter.include_existing_file(&2, &1))
  end
end
