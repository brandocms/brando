defmodule Brando.Trait.Password do
  @moduledoc """
  Hashes pw on changes
  """
  use Brando.Trait

  import Ecto.Changeset

  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  @changeset_phase :before_validate_required

  @doc """
  A blank password on a saved entry keeps the current one.

  The admin never sends the stored hash back to the browser, so a password
  field nobody typed in arrives empty and casts to `nil`. Dropping that change
  before `validate_required` lets the rest of the form save; a new entry still
  needs a password.
  """
  def changeset_mutator(_module, _cfg, %Changeset{data: %{id: id}, changes: %{password: nil}} = changeset, _user, _opts)
      when not is_nil(id) do
    delete_change(changeset, :password)
  end

  def changeset_mutator(_module, _cfg, changeset, _user, _opts), do: changeset

  @doc """
  Hash and salt password if changed.
  """
  def before_save(%{changes: %{password: password}} = changeset, _user) do
    put_change(changeset, :password, Bcrypt.hash_pwd_salt(password))
  end

  def before_save(changeset, _user) do
    changeset
  end
end
