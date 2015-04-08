defmodule Brando.Images.Model.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias Brando.Users.Model.User
  alias Brando.Images.Model.Image
  alias Brando.Images.Model.ImageCategory
  alias Brando.Utils

  @required_fields ~w(name slug image_category_id creator_id)
  @optional_fields ~w(credits order)

  def __name__(:singular), do: "bildeserie"
  def __name__(:plural), do: "bildeserier"

  def __str__(model) do
    model = Brando.get_repo.preload(model, :images)
    image_count = Enum.count(model.images)
    "#{model.name} – #{image_count} bilde(r)."
  end

  use Linguist.Vocabulary
  locale "no", [
    model: [
      id: "ID",
      name: "Navn",
      slug: "URL-tamp",
      credits: "Kreditering",
      order: "Rekkefølge",
      creator: "Opprettet av",
      images: "Bilder",
      image_category: "Bildekategori",
      inserted_at: "Opprettet",
      updated_at: "Oppdatert"
    ]
  ]

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
  If valid, generate a hashed password and insert model to Repo.
  If not valid, return errors from changeset
  """
  def create(params, current_user) do
    params = Utils.Model.put_creator(params, current_user)
    model_changeset = changeset(%__MODULE__{}, :create, params)
    case model_changeset.valid? do
      true ->
        inserted_model = Brando.get_repo().insert(model_changeset)
        {:ok, inserted_model}
      false ->
        {:error, model_changeset.errors}
    end
  end

  @doc """
  Create an `update` changeset for the model by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update model in Repo.
  If not valid, return errors from changeset
  """
  def update(model, params) do
    model_changeset = changeset(model, :update, params)
    case model_changeset.valid? do
      true ->
        {:ok, Brando.get_repo().update(model_changeset)}
      false ->
        {:error, model_changeset.errors}
    end
  end

  def get(slug: slug) do
    from(m in __MODULE__,
         where: m.slug == ^slug,
         preload: [:images, :image_category],
         limit: 1)
    |> Brando.get_repo.one!
  end

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    (from(m in __MODULE__,
      left_join: i in assoc(m, :images),
      where: m.id == ^id,
      order_by: i.order,
      preload: [:creator, :image_category, images: i]))
      |> Brando.get_repo.one!
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
    Brando.Images.Model.Image.delete_dependent_images(record.id)
    Brando.get_repo.delete(record)
  end

  @doc """
  Delete all imageseries dependant on `category_id`
  """
  def delete_dependent_image_series(category_id) do
    image_series =
      from(m in __MODULE__, where: m.image_category_id == ^category_id)
      |> Brando.get_repo.all

    for is <- image_series do
      delete(is)
    end
  end
end