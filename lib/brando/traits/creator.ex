defmodule Brando.Trait.Creator do
  @moduledoc """
  Automatically sets creator to user
  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  relations do
    relation :creator, :belongs_to, module: Brando.Users.User, required: true
  end

  @doc """
  Add creator to changeset
  """
  @changeset_phase :before_validate_required
  def changeset_mutator(_, _cfg, %Changeset{valid?: true} = cs, :system, _), do: cs

  def changeset_mutator(_, _cfg, %Changeset{valid?: true} = cs, user, _) when is_map(user),
    do: Changeset.put_change(cs, :creator_id, user.id)

  def changeset_mutator(_, _cfg, %Changeset{valid?: true} = cs, user_id, _),
    do: Changeset.put_change(cs, :creator_id, user_id)

  def changeset_mutator(_, _, changeset, _, _), do: changeset
end
