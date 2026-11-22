defmodule Brando.Content.Definition.Plan do
  @moduledoc """
  A tenant-bound import plan. Apply always verifies its target state again.

  `mode` is the baseline it compares with: `:lockfile` (the bundle's own,
  from the database it was last imported into) or `:database` (the
  definitions last applied here, `Brando.Content.DefinitionApply`).
  `selection` is nil for every definition, or the UIDs an apply writes (whole
  module trees); `replace` the never-applied definitions it may replace;
  `discard` the definitions edited here since they were applied, whose edit
  it may replace with the files' version.

  Each item has the definition's `action`, `reason`, `state` (`:new`,
  `:in_sync`, `:changed_in_release`, `:changed_in_admin`, `:changed_in_both`,
  `:never_applied` or `:deleted`), the `baseline` it was compared with
  (`:applied`, `:lockfile`, `:replaced`, `:discarded` or nil), its `ModuleDiff` `class`,
  the last apply (`applied`) and admin edit (`edited`) when known, changed
  `fields` and their `diff`, the affected `block_count` and `entry_count`,
  and for an update that removes refs or vars, `removes`: their `keys`
  (`{:ref | :var, key}`) and how many `blocks` hold one of them, in how
  many `entries`. Those blocks keep what they hold as a leftover until it is
  resolved (`Brando.Content.StaleBlocks`).
  """
  alias Brando.Tenant

  defstruct [
    :bundle,
    :scope,
    :fingerprint,
    :creator_id,
    mode: :lockfile,
    selection: nil,
    replace: MapSet.new(),
    discard: MapSet.new(),
    revert: false,
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

  @doc """
  What an update removes and how many of the module's blocks hold it, as
  the plan prints it, or nil when it removes nothing.
  """
  def removal_text(%{removes: %{keys: keys, blocks: blocks, entries: entries}, block_count: total}) do
    what = Enum.map_join(keys, ", ", fn {kind, key} -> "#{kind} #{key}" end)
    it = if length(keys) == 1, do: "it", else: "them"

    held =
      case {blocks, entries} do
        {0, _} -> "none of #{total} blocks hold #{it}"
        {_, 1} -> "#{blocks} of #{total} blocks hold #{it}, 1 entry"
        _ -> "#{blocks} of #{total} blocks hold #{it}, #{entries} entries"
      end

    "removes #{what} (#{held})"
  end

  def removal_text(_item), do: nil

  @doc """
  The `mix brando.modules resolve` command that drops what an update of
  `plan` leaves in blocks, as it runs in the current environment, or nil
  when no block holds it. It names the plan's user, `ID` without one.
  """
  def resolve_command(%__MODULE__{creator_id: user_id}, %{uid: uid, removes: %{keys: keys, blocks: blocks}})
      when blocks > 0 do
    environment =
      if Tenant.enabled?(),
        do: " --site #{Tenant.current_site_key()} --environment #{Tenant.current_environment_key()}",
        else: ""

    drops = Enum.map_join(keys, " ", fn {kind, key} -> "--drop #{kind}:#{key}" end)
    "mix brando.modules resolve --uid #{uid} --user #{user_id || "ID"}#{environment} #{drops} --apply"
  end

  def resolve_command(_plan, _item), do: nil
end
