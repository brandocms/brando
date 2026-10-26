defmodule Brando.Trait.ProtectPassword do
  @moduledoc """
  Protect password and email changes from other users than superusers and the
  user itself. The email is where a password reset link goes, so changing it
  is as good as changing the password.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  @doc """
  Check if the user has the right to change the role
  """
  def changeset_mutator(_, _, changeset, :system, _opts) do
    changeset
  end

  def changeset_mutator(_, _, %{changes: %{password: _}} = changeset, current_user, _opts) do
    if is_nil(changeset.data.id) or allowed?(current_user, changeset.data) do
      changeset
    else
      add_error(
        changeset,
        :password,
        gettext("Only superusers can change the password of other users.")
      )
    end
  end

  def changeset_mutator(_, _, %{changes: %{email: _}} = changeset, current_user, _opts) do
    if is_nil(changeset.data.id) or allowed?(current_user, changeset.data) do
      changeset
    else
      add_error(changeset, :email, gettext("Only superusers can change the email of other users."))
    end
  end

  def changeset_mutator(_, _, changeset, _user, _), do: changeset

  @doc """
  Whether `current_user` (a user or their `Brando.Authorization.Scope`) may
  change the password or email of `user`, or send them a link to reset the
  password: a superuser may for anyone, others only for themselves.
  """
  @spec allowed?(map() | :system, map()) :: boolean()
  def allowed?(:system, _user), do: true
  def allowed?(%Brando.Authorization.Scope{user_id: id}, %{id: id}) when not is_nil(id), do: true
  def allowed?(%{id: id}, %{id: id}) when not is_nil(id), do: true
  def allowed?(current_user, _user), do: Brando.Authorization.Boundary.superuser?(current_user)
end
