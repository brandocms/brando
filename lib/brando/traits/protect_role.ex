defmodule Brando.Trait.ProtectRole do
  @moduledoc """
  Protect user role changes from other users than superusers
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

  def changeset_mutator(_, _, %{changes: %{role: nil}} = changeset, _current_user, _opts) do
    changeset
  end

  def changeset_mutator(_, _, %{changes: %{role: new_role}} = changeset, current_user, _opts) do
    old_role = changeset.data.role
    # check if the user has the right to change the role
    {:ok, user_role_val} = Brando.Type.Role.dump(current_user.role)
    {:ok, new_role_val} = Brando.Type.Role.dump(new_role)
    {:ok, old_role_val} = Brando.Type.Role.dump(old_role || :user)

    cond do
      current_user.role == :superuser ->
        # superuser can change any role
        changeset

      changeset.data.id == nil and new_role_val <= user_role_val ->
        # new user and the new role is lower or equal to the current user
        changeset

      changeset.data.id != nil and user_role_val >= 2 and old_role_val < user_role_val ->
        # user is existing user and the old role is lower than the current user
        changeset

      true ->
        add_error(changeset, :role, gettext("You don't have the right to change the role"))
    end
  end

  def changeset_mutator(_, _, changeset, _user, _), do: changeset
end
