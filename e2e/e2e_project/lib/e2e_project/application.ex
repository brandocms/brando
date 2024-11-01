defmodule E2eProject.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start the Ecto repository
      E2eProject.Repo,
      # Start the Telemetry supervisor
      E2eProjectWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: E2eProject.PubSub},
      # Start the Endpoint (http/https)
      E2eProjectWeb.Endpoint,
      # Start the Presence system
      E2eProject.Presence,
      # Start the Brando supervisor
      Brando
      # Start a worker by calling: E2eProject.Worker.start_link(arg)
      # {E2eProject.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: E2eProject.Supervisor]
    result = Supervisor.start_link(children, opts)
    Brando.System.initialize()

    sql_sandbox = Application.get_env(Brando.config(:otp_app), :sql_sandbox)

    if sql_sandbox do
      Ecto.Adapters.SQL.Sandbox.mode(Brando.repo(), {:shared, self()})
    end

    result
  end



  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    E2eProjectWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
