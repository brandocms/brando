defmodule Brando.Trait.Focal do
  use Brando.Trait

  def after_save(_entry, %{changes: %{path: _}}, _) do
    :ok
  end

  def after_save(entry, %{changes: %{focal: _}}, user) do
    Brando.Images.Processing.recreate_sizes_for_image(entry, user)
  end

  def after_save(_, _, _) do
    :ok
  end

  def changeset_mutator(_module, _config, %{changes: %{focal: _}} = changeset, _user, _opts) do
    Ecto.Changeset.put_change(changeset, :status, :unprocessed)
  end

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
  end
end
