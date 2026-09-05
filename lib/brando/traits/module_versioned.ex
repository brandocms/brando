defmodule Brando.Trait.ModuleVersioned do
  @moduledoc """
  Bumps `Module.version` whenever a save effectively changes the module definition.

  Saving a module migrates every block that uses it, so the version is the marker
  that says *which* revision a block was last migrated to — see
  `Brando.Content.ModuleDiff` for what counts as an effective change, and
  `Brando.Content.Blocks.sync_module/2` for where blocks are stamped.

  A save that changes nothing (or only the changelog note) does not bump, so the
  version stays a meaningful count of definition revisions rather than of clicks
  on Save.

  When it does bump, the bump doubles as an optimistic lock: two editors who open
  the same module and both save cannot silently publish two different "next"
  revisions — the second one gets an `Ecto.StaleEntryError` instead.
  """
  use Brando.Trait

  alias Brando.Content.ModuleDiff
  alias Ecto.Changeset

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    cond do
      # A new module is born at v1; there is nothing to migrate from.
      is_nil(changeset.data.id) ->
        changeset

      # The shared library sets the next version itself when publishing a
      # library revision. Don't second-guess an explicit decision.
      Changeset.changed?(changeset, :version) ->
        changeset

      ModuleDiff.effective?(ModuleDiff.diff(changeset.data, changeset)) ->
        Changeset.optimistic_lock(changeset, :version, &((&1 || 1) + 1))

      true ->
        changeset
    end
  end
end
