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
  Gets the parent app's router
  """
  def router, do: web_module(Router)

  @doc """
  Gets the timezone set for app
  """
  def timezone, do: config(:timezone) || "Europe/Oslo"

  @doc """
  Gets the parent app's endpoint
  """
  def endpoint, do: web_module(Endpoint)

  @doc """
  Gets the parent app's repo
  """
  def repo, do: app_module(Repo)

  @doc """
  Gets the parent app's factory
  """
  def factory, do: app_module(Factory)

  @doc """
  Gets the parent app's gettext module
  """
  def gettext, do: web_module(Gettext)

  @doc """
  Gets the parent app's helpers
  """
  def helpers, do: web_module(Router.Helpers)

  @doc """
  Gets the parent app's authorization module
  """
  def authorization, do: app_module(Authorization)

  @doc """
  Gets the parent app's presence module
  """
  def presence, do: app_module(Presence)

  @doc """
  Gets the parent app's sitemap module
  """
  def sitemap, do: web_module(Sitemap)

  @doc """
  Gets the parent app's pubsub module
  """
  def pubsub, do: app_module(PubSub)

  @doc """
  Gets the parent app's otp name
  """
  def otp_app, do: config(:otp_app)

  @doc """
  Gets the parent app's env
  """
  def env, do: config(:env)

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
