defmodule Brando.Content.Definition.Plan do
  @moduledoc """
  A tenant-bound import plan. Apply always verifies its target state again.

  `mode` is the baseline it compares with: `:lockfile` (the bundle's own,
  from the database it was last imported into) or `:database` (the
  definitions last applied here, `Brando.Content.DefinitionApply`).
  `selection` is nil for every definition, or the UIDs an apply writes (whole
  module trees); `replace` the never-applied definitions it may replace.

  Each item has the definition's `action`, `reason`, `state` (`:new`,
  `:in_sync`, `:changed_in_release`, `:changed_in_admin`, `:changed_in_both`,
  `:never_applied` or `:deleted`), the `baseline` it was compared with
  (`:applied`, `:lockfile`, `:replaced` or nil), its `ModuleDiff` `class`,
  the last apply (`applied`) and admin edit (`edited`) when known, changed
  `fields` and their `diff`, and the affected `block_count` and `entry_count`.
  """
  defstruct [
    :bundle,
    :scope,
    :fingerprint,
    :creator_id,
    mode: :lockfile,
    selection: nil,
    replace: MapSet.new(),
    snapshot_bindings: %{},
    items: [],
    references: %{}
  ]

  @type t :: %__MODULE__{}

  @doc "Whether every selected item is a create, update or no-op."
  def applicable?(%__MODULE__{items: items} = plan),
    do: Enum.all?(items, &(not selected?(plan, &1) or &1.action in [:create, :update, :noop]))

  @doc "Whether an apply of `plan` writes `item` (when it changes)."
  def selected?(%__MODULE__{selection: nil}, _item), do: true
  def selected?(%__MODULE__{selection: selection}, item), do: MapSet.member?(selection, item.uid)
end
