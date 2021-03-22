defmodule Brando.Traits.Password do
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
  @spec changeset_mutator(module, config, changeset, map | :system) :: changeset
  def changeset_mutator(_module, _config, %{valid?: true} = changeset, _user) do
    maybe_update_password(changeset)
  end

  def changeset_mutator(_, _, changeset, _), do: maybe_update_password(changeset)

  defp maybe_update_password(%{changes: %{password: password}} = changeset),
    do: put_change(changeset, :password, Bcrypt.hash_pwd_salt(password))

  defp maybe_update_password(changeset) do
    require Logger
    Logger.error(inspect(changeset.errors, pretty: true))
    changeset
  end
end
