defmodule Brando do
  @moduledoc File.read!("README.md")
  @version Mix.Project.config()[:version]

  @doc """
  Start supervisor
  """
  def start_link(opts), do: Brando.Supervisor.start_link(opts)

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Gets the configuration for `key` under :brando,
  as set in config.exs
  """
  def config(key), do: Application.get_env(:brando, key)

  @doc """
  Gets the parent app's router, as set in config.exs
  """
  def router, do: web_module(Router)

  @doc """
  Gets the timezone set for app
  """
  def timezone, do: config(:timezone) || "Europe/Oslo"

  @doc """
  Gets the parent app's endpoint, as set in config.exs
  """
  def endpoint, do: web_module(Endpoint)

  @doc """
  Gets the parent app's repo, as set in config.exs
  """
  def repo, do: app_module(Repo)

  @doc """
  Gets the parent app's factory, as set in config.exs
  """
  def factory, do: app_module(Factory)

  @doc """
  Gets the parent app's helpers, as set in config.exs
  """
  def helpers, do: web_module(Router.Helpers)

  @doc """
  Gets the parent app's authorization module, as set in config.exs
  """
  def authorization, do: app_module(Authorization)

  @doc """
  Gets the parent app's presence module, as set in config.exs
  """
  def presence, do: app_module(Presence)

  @doc """
  Gets the parent app's otp name, as set in config.exs
  """
  def otp_app, do: config(:otp_app)

  @doc """
  Get Brando version
  """
  def version, do: @version

  @doc """
  Concat the configured application module with `module`
  """
  def app_module(module), do: Module.concat(config(:app_module), module)

  @doc """
  Concat the configured web module with `module`
  """
  def web_module(module), do: Module.concat(config(:web_module), module)
end
