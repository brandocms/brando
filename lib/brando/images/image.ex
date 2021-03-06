defmodule Brando.Image do
  @moduledoc """
  Ecto schema for the Image schema
  and helper functions for dealing with the schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Sequence.Schema
  use Brando.SoftDelete.Schema
  use Brando.Field.Image.Schema
  use Brando.Schema

  import Ecto.Query, only: [from: 2]

  meta :en, singular: "image", plural: "images"
  meta :no, singular: "bilde", plural: "bilder"
  identifier false
  absolute_url false

  @required_fields ~w(image)a
  @optional_fields ~w(sequence image_series_id creator_id deleted_at)a

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

  has_image_field(:image, :db)

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, map) :: any
  def changeset(schema, params, user \\ :system, cfg \\ nil) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_creator(user)
    |> validate_required(@required_fields)
    |> validate_upload({:image, :image}, user, cfg)
  end
end
