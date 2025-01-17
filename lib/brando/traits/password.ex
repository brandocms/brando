defmodule Brando.Trait.Password do
  @moduledoc """
  Hashes pw on changes
  """
  use Brando.Trait

  import Ecto.Changeset

  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

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
