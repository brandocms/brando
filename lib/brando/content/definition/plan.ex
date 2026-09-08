defmodule Brando.Content.Definition.Plan do
  @moduledoc "A tenant-bound import plan. Apply always verifies its target state again."
  defstruct [:bundle, :scope, :fingerprint, :creator_id, items: [], references: %{}]

  @type t :: %__MODULE__{}

  @doc "Whether every item is a create, update or no-op."
  def applicable?(%__MODULE__{items: items}), do: Enum.all?(items, &(&1.action in [:create, :update, :noop]))
end
