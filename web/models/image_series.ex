defmodule Brando.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series model
  and helper functions for dealing with the model.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Sequence, :model

  alias Brando.User
  alias Brando.Image
  alias Brando.ImageCategory

  import Brando.Gettext
  import Ecto.Query, only: [from: 2]
  import Brando.Utils.Model, only: [put_creator: 2]

  @required_fields ~w(name slug image_category_id creator_id)a
  @optional_fields ~w(credits sequence cfg)a

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
  def changeset(model, action, params \\ %{})
  def changeset(model, :create, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> inherit_configuration()
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :update.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :update, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :update, params) do
    cast(model, params, @required_fields ++ @optional_fields)
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
    Brando.repo.one!(
      from m in __MODULE__,
        select: m.slug,
        where: m.id == ^id
    )
  end

  @doc """
  Get all imageseries in category `id`.
  """
  def get_by_category_id(id) do
    Brando.repo.all(
      from m in __MODULE__,
        where: m.image_category_id == ^id,
        order_by: m.sequence,
        preload: [:images]
    )
  end

  @doc """
  Delete `series` from database

  Also deletes all dependent images.
  """
  def delete(series) do
    Brando.Images.Utils.delete_images_for(series_id: series.id)
    Brando.repo.delete!(series)
  end

  @doc """
  Delete all imageseries dependant on `category_id`
  """
  def delete_dependent_image_series(category_id) do
    image_series = Brando.repo.all(
      from m in __MODULE__,
        where: m.image_category_id == ^category_id
    )

    for is <- image_series, do:
      delete(is)
  end

  @doc """
  Before inserting changeset. Copies the series' category config.
  """
  def inherit_configuration(%{changes: %{image_category_id: cat_id, slug: slug}} = cs) do
    do_inherit_configuration(cs, cat_id, slug)
  end

  def inherit_configuration(%{data: %{image_category_id: cat_id, slug: slug}} = cs) do
    do_inherit_configuration(cs, cat_id, slug)
  end

  defp do_inherit_configuration(cs, cat_id, slug) do
    category = Brando.repo.get(ImageCategory, cat_id)
    cfg =
      if slug do
        Map.put(category.cfg, :upload_path, Path.join(Map.get(category.cfg, :upload_path), slug))
      else
        category.cfg
      end
    put_change(cs, :cfg, cfg)
  end

  #
  # Meta

  use Brando.Meta.Model, [
    singular: gettext("imageserie"),
    plural: gettext("imageseries"),
    repr: fn (model) ->
       model = Brando.repo.preload(model, :images)
       image_count = Enum.count(model.images)
       "#{model.name} – #{image_count} #{gettext("image(s)")}."
    end,
    fields: [
      id: gettext("ID"),
      name: gettext("Name"),
      slug: gettext("Slug"),
      cfg: gettext("Configuration"),
      credits: gettext("Credits"),
      sequence: gettext("Sequence"),
      creator: gettext("Creator"),
      images: gettext("Images"),
      image_category: gettext("Image category"),
      image_category_id: gettext("Image category"),
      inserted_at: gettext("Inserted at"),
      updated_at: gettext("Updated at")
    ],
    hidden_fields: []
  ]
end
