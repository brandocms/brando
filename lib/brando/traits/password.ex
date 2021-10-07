defmodule Brando.Trait.Password do
  @moduledoc """
  Hashes pw on changes
  """
  use Brando.Trait
  alias Ecto.Changeset
  import Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  @doc """
  Update password if changed
  """
  def changeset_mutator(_module, _config, %{valid?: true} = changeset, _user, _) do
    maybe_update_password(changeset)
  end

  def changeset_mutator(_, _, changeset, _, _), do: maybe_update_password(changeset)

  defp maybe_update_password(%{changes: %{password: password}} = changeset) do
    put_change(changeset, :password, Bcrypt.hash_pwd_salt(password))
  end

  defp maybe_update_password(changeset) do
    changeset
  end
end
