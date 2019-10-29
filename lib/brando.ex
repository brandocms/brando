defmodule Brando do
  use Application

  @moduledoc File.read!("README.md")
  @version Mix.Project.config()[:version]

  def start(_type, _args) do
    Brando.Supervisor.start_link()
  end

  @doc """
  Gets the configuration for `module` under :brando,
  as set in config.exs
  """
  def config(module), do: Application.get_env(:brando, module)

  @doc """
  Gets the parent app's router, as set in config.exs
  """
  def router, do: config(:router)

  @doc """
  Gets the parent app's endpoint, as set in config.exs
  """
  def endpoint, do: config(:endpoint)

  @doc """
  Gets the parent app's repo, as set in config.exs
  """
  def repo, do: config(:repo)

  @doc """
  Gets the parent app's factory, as set in config.exs
  """
  def factory, do: config(:factory)

  @doc """
  Gets the parent app's helpers, as set in config.exs
  """
  def helpers, do: config(:helpers)

  @doc """
  Gets the parent app's otp name, as set in config.exs
  """
  def otp_app, do: config(:otp_app)

  @doc """
  Get Brando version
  """
  def version, do: @version
end
