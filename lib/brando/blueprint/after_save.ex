defmodule Brando.Blueprint.AfterSave do
  @moduledoc """
  What runs after an entry is saved: each trait's `after_save/3`, then work
  that belongs to the whole Blueprint rather than to a trait — enqueueing the
  sync of a synchronized translation source (`Brando.Translations`).

  This is a runtime boundary. A trait is a compile-time dependency of every
  Blueprint that declares it, so whatever a trait calls joins those
  Blueprints' compile-connected component. `Brando.Translations` reaches back
  to the Blueprints through content and identifiers, and calling it from the
  translatable trait closed a cycle that `mix xref` rejects. Nothing compiles
  against this module; it is only called when an entry has been saved.
  """

  @doc """
  Runs the after-save work for `entry` of `schema`. Returns the traits'
  results, as `Brando.Trait.run_trait_after_save_callbacks/4` does.
  """
  @spec run(module(), struct(), Ecto.Changeset.t(), map() | atom()) :: list()
  def run(schema, entry, changeset, user) do
    results = Brando.Trait.run_trait_after_save_callbacks(schema, entry, changeset, user)
    # A no-op unless the schema is synchronized and the entry is a group's source.
    Brando.Translations.source_saved(entry, minor: false)
    results
  end
end
