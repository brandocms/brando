defmodule Brando.Trait.ProtectRole do
  @moduledoc """
  Protect user role changes from other users than superusers
  """
  use Brando.Trait
  alias Brando.Type.Role
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
    if allowed?(current_user, changeset.data, new_role),
      do: changeset,
      else: add_error(changeset, :role, gettext("You don't have the right to change the role"))
  end

  def changeset_mutator(_, _, changeset, _user, _), do: changeset

  @doc """
  Whether `current_user` may give `user` the role `new_role`: a superuser any
  role; others a new user a role up to their own, and an admin an existing
  user below their role a role up to their own.
  """
  @spec allowed?(map() | :system, map(), atom()) :: boolean()
  def allowed?(:system, _user, _new_role), do: true
  def allowed?(%{role: :superuser}, _user, _new_role), do: true

  def allowed?(%{role: role}, user, new_role) when not is_nil(role) do
    {:ok, user_role_val} = Role.dump(role)
    {:ok, new_role_val} = Role.dump(new_role)
    {:ok, old_role_val} = Role.dump(user.role || :user)

    if is_nil(user.id),
      do: new_role_val <= user_role_val,
      else: user_role_val >= 2 and old_role_val < user_role_val and new_role_val <= user_role_val
  end

  def allowed?(_current_user, _user, _new_role), do: false
end
