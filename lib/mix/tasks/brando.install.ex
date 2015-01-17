defmodule Mix.Tasks.Brando.Install do
  use Mix.Task
  alias Phoenix.Naming
  import Mix.Brando

  @shortdoc "Generates files for Brando."

  @moduledoc """
  Generates admin, common files as well as Users; Brando's user management
  """

  def run(args) do
    run(args, nil)
  end

  def run(_, _opts) do
    application_atom   = Mix.Project.config()[:app]
    application_name   = Naming.camelize(application_atom)

    binding = [application_atom: application_atom,
               application_name: application_name]

    copy_from brando_template_dir, "./", {}, &EEx.eval_file(&1, binding)
    copy_from users_template_dir, "./", {}, &EEx.eval_file(&1, binding)
    copy_from static_dir, Path.join("./", "priv/static"), application_name, &File.read!(&1)
    Mix.shell.info """
    ------------------------------------------------------------------
    Add to `web/router.ex`:
        pipeline :admin do
          plug :accepts, ~w(html json)
          plug :fetch_session
          plug <%= application_name %>.Plugs.LoginRequired
        end

        scope "/admin", as: :admin do
          pipe_through :admin
          Users_resources "/brukere"
          get "/", <%= application_name %>.Dashboard.Admin.DashboardController, :dashboard
        end

        scope "/" do
          pipe_through :browser
          get "/login", <%= application_name %>.AuthController, :login
          post "/login", <%= application_name %>.AuthController, :login
          get "/logout", <%= application_name %>.AuthController, :logout
        end

    Add to lib/your_app.ex
        children = [
          worker(YourApp.Repo, [])
        ]

    Add to mix.exs
        def application do
          [mod: {MyApp, []},
            applications: [:phoenix, :cowboy, :logger, :postgrex, :ecto, :bcrypt]]
        end
    ------------------------------------------------------------------
    """
  end

  def brando_template_dir do
    Application.app_dir(:brando, "priv/templates/brando")
  end

  def users_template_dir do
    Application.app_dir(:brando, "priv/templates/users")
  end

  def static_dir do
    Application.app_dir(:brando, "priv/static")
  end
end