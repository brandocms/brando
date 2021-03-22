defmodule Brando.Traits.Gallery do
  @moduledoc """

  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  relations do
    relation :image_series, :belongs_to,
      module: Brando.ImageSeries,
      cast_assoc: [with: {Brando.ImageSeries, :changeset}, user: true]
  end

  @doc """
  Add creator to changeset
  """
  @changeset_phase :before_validate_required
  @spec changeset_mutator(module, config, changeset, map | :system) :: changeset
  def changeset_mutator(_, _, %Changeset{valid?: true} = cs, :system), do: cs

  def changeset_mutator(_, _, %Changeset{valid?: true} = cs, user) when is_map(user),
    do: Changeset.put_change(cs, :creator_id, user.id)

  def changeset_mutator(_, _, %Changeset{valid?: true} = cs, user_id),
    do: Changeset.put_change(cs, :creator_id, user_id)

  def changeset_mutator(_, _, changeset, _), do: changeset
end
