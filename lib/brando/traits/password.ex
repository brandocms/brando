defmodule Brando.Trait.Password do
  @moduledoc """
  Hashes a changed password with Bcrypt when the entry is written.

  Pass the password in plain text, through the admin form or a context call
  such as `Brando.Users.create_user/2`: the schema's validations (length,
  confirmation) check the plain text, and the hash replaces it in
  `prepare_changes/2`, just before the write. Code that inserts a struct
  directly, without a changeset, hashes the password itself.
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

  # A saved user's password changes only through `Brando.Users`'s password
  # functions (`update_user_password/4`, `reset_user_password/2`,
  # `set_user_password/3`), which check who asks and end the user's
  # sessions and connected tools. `update_user/3` refuses it.
  def changeset_mutator(
        Brando.Users.User,
        _cfg,
        %Changeset{data: %{id: id}, changes: %{password: _}} = changeset,
        _user,
        _opts
      )
      when not is_nil(id) do
    add_error(changeset, :password, "is changed with the password functions in Brando.Users")
  end

  def changeset_mutator(_module, _cfg, changeset, _user, _opts), do: prepare_changes(changeset, &hash_password/1)

  @doc """
  Hashes and salts the password if it changed.
  """
  def hash_password(%{changes: %{password: password}} = changeset) when is_binary(password) do
    put_change(changeset, :password, Bcrypt.hash_pwd_salt(password))
  end

  def hash_password(changeset), do: changeset
end
