defmodule Brando do
  @moduledoc """
  Brando is a set of helping hands for building Twined applications.
  """

  @doc """
  Gets the configuration for `module` under :brando,
  as set in config.exs
  """
  def config(module), do: Application.get_env(:brando, module, [])

  @doc """
  Gets the parent app's router, as set in config.exs
  """
  def get_router, do: config(:router)

  @doc """
  Gets the parent app's endpoint, as set in config.exs
  """
  def get_endpoint, do: config(:endpoint)

  @doc """
  Gets the parent app's repo, as set in config.exs
  """
  def get_repo, do: config(:repo)

  @doc """
  Gets the parent app's helpers, as set in config.exs
  """
  def get_helpers, do: Module.concat(get_router, "Helpers")

  defprotocol Render do
    @moduledoc """
    Render entities to something that can be showed publicly.
    Used, for example, when converting entities to JSON responses.
    """

    @spec render(term) :: Dict.t
    def render(entity)
  end
end