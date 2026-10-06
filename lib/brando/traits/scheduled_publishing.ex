defmodule Brando.Trait.ScheduledPublishing do
  @moduledoc """
  Adds `publish_at`.

  An entry that is published without a `publish_at` gets the time it was
  written. This runs when the changeset is written (`prepare_changes/2`), so it
  applies to every save — the admin form, context mutations, revisions and
  jobs — and not to form validation, which never writes.
  """
  use Brando.Trait

  alias Brando.Trait.ScheduledPublishing.Compiler

  import Ecto.Changeset

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @impl true
  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    prepare_changes(changeset, &stamp_publish_at/1)
  end

  # Status changed to :published, but no publish_at set = set to utc_now
  @doc false
  def stamp_publish_at(%{changes: %{status: :published}} = changeset) do
    if get_field(changeset, :publish_at) == nil do
      put_change(changeset, :publish_at, DateTime.truncate(DateTime.utc_now(), :second))
    else
      changeset
    end
  end

  def stamp_publish_at(changeset), do: changeset
end
