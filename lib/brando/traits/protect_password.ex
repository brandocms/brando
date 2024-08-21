defmodule Brando.Trait.ProtectPassword do
  @moduledoc """
  Protect password changes from other users than superusers and the user itself
  """
  use Brando.Trait
  alias Ecto.Changeset
  import Ecto.Changeset
  use Gettext, backend: Brando.Gettext

  @type changeset :: Changeset.t()
  @type config :: list()

  @doc """
  Check if the user has the right to change the role
  """
  def changeset_mutator(_, _, changeset, :system, _opts) do
    changeset
  end

  def changeset_mutator(_, _, %{changes: %{password: _}} = changeset, current_user, _opts) do
    cond do
      current_user.role == :superuser ->
        changeset

      changeset.data.id == nil ->
        changeset

      current_user.id == changeset.data.id ->
        changeset

      true ->
        add_error(
          changeset,
          :password,
          gettext("Only superusers can change the password of other users.")
        )
    end
  end

  def changeset_mutator(_, _, changeset, _user, _), do: changeset
end
