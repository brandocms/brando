defmodule Brando.Trait.ProtectPassword do
  @moduledoc """
  Protect password changes from other users than superusers and the user itself
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

  def changeset_mutator(_, _, changeset, _user, _), do: changeset

  @doc """
  Whether `current_user` may change the password of `user`, or send them a
  link to reset it: a superuser may for anyone, others only for themselves.
  """
  @spec allowed?(map() | :system, map()) :: boolean()
  def allowed?(:system, _user), do: true
  def allowed?(%{id: id}, %{id: id}) when not is_nil(id), do: true

  def allowed?(current_user, _user) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.Engine.superuser?(Brando.Authorization.Scope.installation(current_user)),
      else: current_user.role == :superuser
  end
end
