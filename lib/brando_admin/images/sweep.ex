defmodule BrandoAdmin.Images.Sweep do
  @moduledoc """
  "Sort by use" for the image library: `BrandoAdmin.Media.Sweep` with the
  asset type set to `:image`. See that module for what a sort does and how a
  site ranks its types (`config :brando, Brando.Images, sweep_priority: [...]`).
  """

  alias BrandoAdmin.Media.Sweep

  @doc "What sorting image folder `folder_id` would do. See `BrandoAdmin.Media.Sweep.plan/2`."
  @spec plan(integer() | nil) :: {:ok, Sweep.plan()} | {:error, :not_found}
  def plan(folder_id), do: Sweep.plan(:image, folder_id)

  @doc "Moves the planned images. See `BrandoAdmin.Media.Sweep.apply/2`."
  @spec apply(Sweep.plan(), keyword()) :: {:ok, map()}
  defdelegate apply(plan, opts \\ []), to: Sweep

  @doc "Puts back what `apply/2` moved. See `BrandoAdmin.Media.Sweep.undo/1`."
  @spec undo(map()) :: {:ok, non_neg_integer()}
  defdelegate undo(result), to: Sweep
end
