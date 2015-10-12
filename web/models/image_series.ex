defmodule Brando.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Sequence, :model
  import Ecto.Query, only: [from: 2]
  import Brando.Utils.Model, only: [put_creator: 2]
  alias Brando.User
  alias Brando.Image
  alias Brando.ImageCategory

  @required_fields ~w(name slug image_category_id creator_id)
  @optional_fields ~w(credits sequence cfg)

  before_insert __MODULE__, :inherit_configuration

  schema "imageseries" do
    field :name, :string
    field :slug, :string
    field :credits, :string
    field :cfg, Brando.Type.ImageConfig
    belongs_to :creator, User
    belongs_to :image_category, ImageCategory
    has_many :images, Image
    sequenced
    timestamps
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, action, params \\ :empty)
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
    |> cast(params, @required_fields, @optional_fields)
  end

  @doc """
  Create a changeset for the model by passing `params`.
  If valid, generate a hashed password and insert model to Brando.repo.
  If not valid, return errors from changeset
  """
  def create(params, current_user) do
    %__MODULE__{}
    |> put_creator(current_user)
    |> changeset(:create, params)
    |> Brando.repo.insert
  end

  @doc """
  Create an `update` changeset for the model by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update model in Brando.repo.
  If not valid, return errors from changeset
  """
  def update(model, params) do
    model
    |> changeset(:update, params)
    |> Brando.repo.update
  end

  def get_slug(id: id) do
    q = from m in __MODULE__,
             select: m.slug,
             where: m.id == ^id
    Brando.repo.one!(q)
  end

  @doc """
  Before insert callback. Copies the series' category config.
  """
  def inherit_configuration(changeset) do
    category = Brando.repo.get(ImageCategory, changeset.changes.image_category_id)
    put_change(changeset, :cfg, category.cfg)
  end

  @doc """
  Get all imageseries in category `id`.
  """
  def get_by_category_id(id) do
    q = from m in __MODULE__,
             where: m.image_category_id == ^id,
             order_by: m.sequence,
             preload: [:images]
    Brando.repo.all(q)
  end

  @doc """
  Delete `record` from database

  Also deletes all dependent images.
  """
  def delete(record) do
    Brando.Image.delete_dependent_images(record.id)
    Brando.repo.delete!(record)
  end

  @doc """
  Recreates all image sizes in imageseries.
  """
  def recreate_sizes(image_series_id) do
    q = from m in __MODULE__,
             preload: :images,
             where: m.id == ^image_series_id
    image_series = Brando.repo.one!(q)
    for image <- image_series.images do
      Brando.Image.recreate_sizes(image)
    end
  end

  @doc """
  Delete all imageseries dependant on `category_id`
  """
  def delete_dependent_image_series(category_id) do
    q = from m in __MODULE__,
             where: m.image_category_id == ^category_id
    image_series = Brando.repo.all(q)

    for is <- image_series, do:
      delete(is)
  end

  #
  # Meta

  use Brando.Meta.Model, [
    no: [
      singular: "bildeserie",
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
               sequence: "Rekkefølge",
               cfg: "Konfigurasjon",
               creator: "Opprettet av",
               images: "Bilder",
               image_category: "Bildekategori",
               image_category_id: "Bildekategori",
               inserted_at: "Opprettet",
               updated_at: "Oppdatert"],
      hidden_fields: []],
    en: [
      singular: "imageserie",
      plural: "imageseries",
      repr: fn (model) ->
         model = Brando.repo.preload(model, :images)
         image_count = Enum.count(model.images)
         "#{model.name} – #{image_count} image(s)."
      end,
      fields: [id: "ID",
               name: "Name",
               slug: "Slug",
               cfg: "Configuration",
               credits: "Credits",
               sequence: "Sequence",
               creator: "Creator",
               images: "Images",
               image_category: "Image category",
               image_category_id: "Image category",
               inserted_at: "Inserted at",
               updated_at: "Updated at"],
      hidden_fields: []]]
end
