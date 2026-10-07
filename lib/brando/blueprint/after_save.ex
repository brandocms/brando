defmodule Brando.Blueprint.AfterSave do
  @moduledoc """
  Runs each trait's `after_save/3` once an entry is saved.

  The admin form, revisions and proposals call this after their saves. Work
  every save needs regardless of where it came from — enqueueing the sync of
  synchronized translations (`Brando.Translations.source_saved/2`) — belongs
  to the save itself: `Brando.Query.Mutations` does it for context saves, and
  code that writes entries past the context (revisions, content transfer)
  calls it directly.

  This is a runtime boundary. A trait is a compile-time dependency of every
  Blueprint that declares it, so whatever a trait calls joins those
  Blueprints' compile-connected component. Nothing compiles against this
  module; it is only called when an entry has been saved.
  """

  @doc """
  Runs the traits' after-save callbacks for `entry` of `schema` and returns
  their results, as `Brando.Trait.run_trait_after_save_callbacks/4` does.
  """
  @spec run(module(), struct(), Ecto.Changeset.t(), map() | atom()) :: list()
  def run(schema, entry, changeset, user) do
    results = Brando.Trait.run_trait_after_save_callbacks(schema, entry, changeset, user)
    # Notes anchored to blocks follow what was saved: detached when their
    # block is gone, attached again when a revision brings it back.
    Brando.Notes.entry_saved(schema, entry)
    results
  end
end
