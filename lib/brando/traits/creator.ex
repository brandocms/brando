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
  def changeset_mutator(_, _cfg, changeset, :system, _), do: changeset

  def changeset_mutator(_, _cfg, %{data: %{id: id}, changes: %{}} = changeset, _, _)
      when not is_nil(id) do
    changeset
  end

  def changeset_mutator(_, _cfg, changeset, user, _) when is_map(user) do
    Changeset.put_change(changeset, :creator_id, user.id)
  end

  def changeset_mutator(_, _cfg, changeset, user_id, _) do
    Changeset.put_change(changeset, :creator_id, user_id)
  end
end
