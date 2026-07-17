defmodule Brando.Blueprint.AssociationKey do
  @moduledoc """
  Derives the persisted field key for Blueprint relations and assets.

  Keeping this compile-time transformation primitive independent of the main
  Blueprint module prevents Spark transformers from depending on the complete
  schema-generation implementation.
  """

  @foreign_key_types [:belongs_to, :file, :image, :video]

  @doc """
  Returns the foreign-key field for singular associations and the association
  name for collection-style relations. Custom `belongs_to` foreign keys are
  respected.

  ## Examples

      iex> Brando.Blueprint.AssociationKey.for(%{type: :image, name: :cover})
      :cover_id

      iex> Brando.Blueprint.AssociationKey.for(%{type: :has_many, name: :items})
      :items

      iex> Brando.Blueprint.AssociationKey.for(%{
      ...>   type: :belongs_to,
      ...>   name: :creator,
      ...>   opts: %{foreign_key: :owner_id}
      ...> })
      :owner_id
  """
  @spec for(%{required(:type) => atom(), required(:name) => atom(), optional(:opts) => map()}) :: atom()
  def for(%{type: :belongs_to, name: name, opts: opts}) do
    Map.get(opts, :foreign_key, :"#{name}_id")
  end

  def for(%{type: type, name: name}) when type in @foreign_key_types, do: :"#{name}_id"
  def for(%{name: name}), do: name
end
