defmodule Brando do

  def config(module), do: Application.get_env(:brando, module, [])

  def get_router, do: config(:router)

  def get_endpoint, do: config(:endpoint)

  def get_repo, do: config(:repo)

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