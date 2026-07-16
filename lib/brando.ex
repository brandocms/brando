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
  defdelegate config(key), to: Brando.RuntimeConfig, as: :get

  defdelegate config(module, key), to: Brando.RuntimeConfig, as: :get

  @doc """
  Gets the parent app's router
  """
  def router, do: web_module(Router)

  @doc """
  Gets the timezone set for app
  """
  def timezone, do: config(:timezone) || "Europe/Oslo"

  @doc """
  Gets the default video upload strategy
  """
  def default_video_upload_strategy, do: config(:default_video_upload_strategy) || :local

  @doc """
  Gets the parent app's endpoint
  """
  defdelegate endpoint(), to: Brando.RuntimeConfig

  @doc """
  Gets the parent app's live preview module
  """
  def live_preview, do: web_module(LivePreview)

  @doc """
  Gets the parent app's repo
  """
  def repo, do: config(:repo_module)

  @doc """
  Gets the parent app's factory
  """
  def factory, do: app_module(Factory)

  @doc """
  Gets the parent app's gettext module
  """
  defdelegate gettext(), to: Brando.RuntimeConfig

  @doc "Gets the parent app's admin Gettext module."
  def gettext_admin, do: admin_module(Gettext)

  @doc """
  Gets the parent app's helpers
  """
  defdelegate helpers(), to: Brando.RuntimeConfig, as: :router_helpers

  @doc "Gets the parent app's router helpers."
  defdelegate routes(), to: Brando.RuntimeConfig, as: :router_helpers

  @doc """
  Gets the parent app's authorization module
  """
  def authorization, do: app_module(Authorization)

  @doc """
  Gets the parent app's filter module
  """
  def filters, do: web_module(Villain.Filters)

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
  defdelegate app_module(module), to: Brando.RuntimeConfig

  @doc """
  Concat the configured application module with `module`
  """
  defdelegate admin_module(module), to: Brando.RuntimeConfig

  @doc """
  Concat the configured web module with `module`
  """
  defdelegate web_module(module), to: Brando.RuntimeConfig
end
