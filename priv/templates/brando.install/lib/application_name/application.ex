defmodule <%= application_module %>.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start the Ecto repository
      <%= application_module %>.Repo,
      # Start the Telemetry supervisor
      <%= application_module %>Web.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: <%= application_module %>.PubSub},
      # Start the Endpoint (http/https)
      <%= application_module %>Web.Endpoint,
      # Start the Presence system
      <%= application_module %>.Presence,
      # Start the Brando supervisor
      Brando
      # Start a worker by calling: <%= application_module %>.Worker.start_link(arg)
      # {<%= application_module %>.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: <%= application_module %>.Supervisor]
    result = Supervisor.start_link(children, opts)
    Brando.System.initialize()
    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    <%= application_module %>Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
