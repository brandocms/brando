defmodule Brando.Image do
  @moduledoc """
  Ecto schema for the Image schema
  and helper functions for dealing with the schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Sequence, :schema
  use Brando.SoftDelete.Schema

  import Ecto.Query, only: [from: 2]

  @required_fields ~w(image image_series_id)a
  @optional_fields ~w(sequence creator_id deleted_at)a

  @derive {Jason.Encoder,
           only: [
             :id,
             :image,
             :creator,
             :creator_id,
             :image_series_id,
             :image_series,
             :sequence,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}

  schema "images_images" do
    field :image, Brando.Type.Image
    belongs_to :creator, Brando.Users.User
    belongs_to :image_series, Brando.ImageSeries
    sequenced()
    timestamps()
    soft_delete()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, :create | :update, Map.t()) :: any
  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
  end

  @doc """
  Get all images in series `id`.
  """
  def for_series_id(id) do
    from m in __MODULE__,
      where: m.image_series_id == ^id,
      order_by: m.sequence
  end
end
