defmodule Brando.Image do
  @moduledoc """
  Ecto schema for the Image schema
  and helper functions for dealing with the schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Sequence, :schema
  use Brando.Images.Upload

  import Brando.Gettext
  import Brando.Utils.Schema, only: [put_creator: 2]
  import Ecto.Query, only: [from: 2]
  import Brando.Images.Utils

  @required_fields ~w(image image_series_id)a
  @optional_fields ~w(sequence creator_id)a

  schema "images" do
    field :image, Brando.Type.Image
    belongs_to :creator, Brando.User
    belongs_to :image_series, Brando.ImageSeries
    sequenced
    timestamps
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid
  changeset when action is :create.

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, :create | :update, Keyword.t) :: t
  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid
  changeset when action is :update.

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :update, params)

  """
  def changeset(schema, :update, params) do
    cast(schema, params, [], @required_fields ++ @optional_fields)
  end

  @doc """
  Create a changeset for the schema by passing `params`.
  If not valid, return errors from changeset
  """
  @spec create(%{binary => term} | %{atom => term}, Brando.User.t) :: {:ok, t} | {:error, Keyword.t}
  def create(params, user) do
    %__MODULE__{}
    |> put_creator(user)
    |> changeset(:create, params)
    |> Brando.repo.insert
  end

  @doc """
  Create an `update` changeset for the schema by passing `params`.
  If valid, update schema in Brando.repo.
  If not valid, return errors from changeset
  """
  @spec update(t, %{binary => term} | %{atom => term}) :: {:ok, t} | {:error, Keyword.t}
  def update(schema, params) do
    schema
    |> changeset(:update, params)
    |> Brando.repo.update
  end

  @doc """
  Updates the `schema`'s image JSON field with `title` and `credits`
  """
  def update_image_meta(schema, title, credits) do
    image =
      schema.image
      |> Map.put(:title, title)
      |> Map.put(:credits, credits)

    # TODO: Return changeset instead?

    update(schema, %{"image" => image})
  end

  @doc """
  Get all images in series `id`.
  """
  def for_series_id(id) do
    from m in __MODULE__,
      where: m.image_series_id == ^id,
      order_by: m.sequence
  end

  @doc """
  Delete `record` from database

  Also deletes all dependent image sizes.
  """
  def delete(ids) when is_list(ids) do
    q       = from m in __MODULE__, where: m.id in ^ids
    records = Brando.repo.all(q)

    for record <- records, do:
      {:ok, _} = delete_original_and_sized_images(record, :image)

    Brando.repo.delete_all(q)
  end

  #
  # Meta

  use Brando.Meta.Schema, [
    singular: gettext("image"),
    plural: gettext("images"),
    repr: &("#{&1.id} | #{&1.image.path}"),
    fields: [
      id: gettext("ID"),
      image: gettext("Image"),
      sequence: gettext("Sequence"),
      creator: gettext("Creator"),
      image_series: gettext("Image series"),
      inserted_at: gettext("Inserted at"),
      updated_at: gettext("Updated at")
    ],
  ]
end
