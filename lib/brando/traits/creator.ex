defmodule Brando.Trait.Creator do
  @moduledoc """
  Automatically sets creator to user
  """
  use Brando.Trait

  alias Brando.Trait.Creator.Compiler
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @doc """
  Add creator to changeset
  """
  @changeset_phase :before_validate_required
  @impl true
  def changeset_mutator(_, _cfg, changeset, :system, _), do: changeset

  # Skip setting creator for existing records that already have a creator and no changes.
  # Matches on %Ecto.Changeset{}.changes directly — this is stable Ecto struct layout.
  def changeset_mutator(_, _cfg, %{data: %{id: id, creator_id: creator_id}, changes: changes} = changeset, _, _)
      when not is_nil(id) and not is_nil(creator_id) and changes == %{} do
    changeset
  end

  def changeset_mutator(_, _cfg, changeset, user, _) when is_map(user) do
    Changeset.put_change(changeset, :creator_id, user.id)
  end

  def changeset_mutator(_, _cfg, changeset, user_id, _) do
    Changeset.put_change(changeset, :creator_id, user_id)
  end
end
