defmodule Brando.SoftDelete do
  @doc """
  Check if `module` implements soft deletion
  """
  def is_soft_deletable(module) do
    {:__soft_delete__, 0} in module.__info__(:functions)
  end
end
