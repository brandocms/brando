defmodule Brando.Traits.Creator do
  @moduledoc """
  Automatically sets creator to user
  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()

  relations do
    relation :creator, :belongs_to, module: Brando.Users.User, required: true
  end

  @doc """
  Add creator to changeset
  """
  @spec changeset_mutator(module, changeset, map | :system) :: changeset
  def changeset_mutator(_, %Changeset{} = cs, :system), do: cs

  def changeset_mutator(_, %Changeset{} = cs, user) when is_map(user),
    do: Changeset.put_change(cs, :creator_id, user.id)

  def changeset_mutator(_, %Changeset{} = cs, user_id),
    do: Changeset.put_change(cs, :creator_id, user_id)

  def changeset_mutator(_, params, :system), do: params
end
