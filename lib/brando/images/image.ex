defmodule Brando.Image do
  @moduledoc """
  Ecto schema for the Image schema
  and helper functions for dealing with the schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Sequence, :schema

  import Brando.Gettext
  import Brando.Images.Optimize, only: [optimize: 2]

  import Ecto.Query, only: [from: 2]

  @required_fields ~w(image image_series_id)a
  @optional_fields ~w(sequence creator_id)a

  schema "images" do
    field :image, Brando.Type.Image
    belongs_to :creator, Brando.User
    belongs_to :image_series, Brando.ImageSeries
    sequenced()
    timestamps()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, :create | :update, Keyword.t()) :: t
  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> optimize(:image)
  end

  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> optimize(:image)
  end

  @doc """
  Get all images in series `id`.
  """
  def for_series_id(id) do
    from m in __MODULE__,
      where: m.image_series_id == ^id,
      order_by: m.sequence
  end

  #
  # Meta

  use Brando.Meta.Schema,
    singular: gettext("image"),
    plural: gettext("images"),
    repr: &"#{&1.id} | #{&1.image.path}",
    fields: [
      id: gettext("ID"),
      image: gettext("Image"),
      sequence: gettext("Sequence"),
      creator: gettext("Creator"),
      image_series: gettext("Image series"),
      inserted_at: gettext("Inserted at"),
      updated_at: gettext("Updated at")
    ]
end
