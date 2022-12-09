defmodule Brando.Trait.Focal do
  use Brando.Trait

  def changeset_mutator(_module, _config, %{changes: %{focal: _}} = changeset, _user, _opts) do
    Ecto.Changeset.put_change(changeset, :status, :unprocessed)
  end

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
  end
end
