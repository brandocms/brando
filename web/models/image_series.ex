defmodule Brando.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  import Ecto.Query, only: [from: 2]
  import Brando.Utils.Model, only: [put_creator: 2]
  alias Brando.User
  alias Brando.Image
  alias Brando.ImageCategory

  @required_fields ~w(name slug image_category_id creator_id)
  @optional_fields ~w(credits order)

  schema "imageseries" do
    field :name, :string
    field :slug, :string
    field :credits, :string
    field :order, :integer
    belongs_to :creator, User
    belongs_to :image_category, ImageCategory
    has_many :images, Image
    timestamps
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :create, params) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :update.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :update, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :update, params) do
    model
    |> cast(params, [], @required_fields ++ @optional_fields)
  end

  @doc """
  Create a changeset for the model by passing `params`.
  If valid, generate a hashed password and insert model to Brando.repo.
  If not valid, return errors from changeset
  """
  def create(params, current_user) do
    model_changeset =
      %__MODULE__{}
      |> put_creator(current_user)
      |> changeset(:create, params)
    case model_changeset.valid? do
      true  -> {:ok, Brando.repo.insert(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  @doc """
  Create an `update` changeset for the model by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update model in Brando.repo.
  If not valid, return errors from changeset
  """
  def update(model, params) do
    model_changeset = model |> changeset(:update, params)
    case model_changeset.valid? do
      true ->  {:ok, Brando.repo.update(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  def get_slug(id: id) do
    from(m in __MODULE__,
      select: m.slug,
      where: m.id == ^id)
      |> Brando.repo.one!
  end

  def get(slug: slug) do
    from(m in __MODULE__,
         where: m.slug == ^slug,
         preload: [:images, :image_category],
         limit: 1)
    |> Brando.repo.one!
  end

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    (from(m in __MODULE__,
      left_join: i in assoc(m, :images),
      where: m.id == ^id,
      order_by: i.sequence,
      preload: [:creator, :image_category, images: i]))
      |> Brando.repo.one
  end

  @doc """
  Get model by `val` or raise `Ecto.NoResultsError`.
  """
  def get!(val) do
    get(val) || raise Ecto.NoResultsError, queryable: __MODULE__
  end

  @doc """
  Delete `record` from database

  Also deletes all dependent images.
  """
  def delete(record) do
    Brando.Image.delete_dependent_images(record.id)
    Brando.repo.delete(record)
  end

  @doc """
  Delete all imageseries dependant on `category_id`
  """
  def delete_dependent_image_series(category_id) do
    image_series =
      from(m in __MODULE__, where: m.image_category_id == ^category_id)
      |> Brando.repo.all

    for is <- image_series, do:
      delete(is)
  end

  #
  # Meta

  use Brando.Meta,
    [singular: "bildeserie",
     plural: "bildeserier",
     repr: fn (model) ->
        model = Brando.repo.preload(model, :images)
        image_count = Enum.count(model.images)
        "#{model.name} – #{image_count} bilde(r)."
     end,
     fields: [id: "ID",
              name: "Navn",
              slug: "URL-tamp",
              credits: "Kreditering",
              order: "Rekkefølge",
              creator: "Opprettet av",
              images: "Bilder",
              image_category: "Bildekategori",
              inserted_at: "Opprettet",
              updated_at: "Oppdatert"]]
end