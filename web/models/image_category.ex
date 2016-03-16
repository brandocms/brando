defmodule Brando.ImageCategory do
  @moduledoc """
  Ecto schema for the Image Category model
  and helper functions for dealing with the model.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :model

  alias Brando.User
  alias Brando.ImageSeries

  import Brando.Gettext
  import Brando.Utils.Model, only: [put_creator: 2]
  import Ecto.Query, only: [from: 2]

  @required_fields ~w(name slug creator_id)a
  @optional_fields ~w(cfg)a

  schema "imagecategories" do
    field :name, :string
    field :slug, :string
    field :cfg, Brando.Type.ImageConfig
    belongs_to :creator, User
    has_many :image_series, ImageSeries
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
    cast(model, params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
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
    path = Map.get(params, "slug", "default")

    default_config =
      Brando.Images
      |> Brando.config
      |> Keyword.get(:default_config)
      |> Map.put(:upload_path, Path.join("images", path))

    %__MODULE__{}
    |> put_creator(current_user)
    |> changeset(:create, params)
    |> put_change(:cfg, default_config)
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

  @doc """
  Returns the model's slug
  """
  def get_slug(id: id) do
    Brando.repo.one!(
      from m in __MODULE__,
        select: m.slug,
        where: m.id == ^id
    )
  end

  @doc """
  Get all records. Ordered by `id`.
  """
  def with_image_series_and_images(query) do
    from m in query,
      left_join: is in assoc(m, :image_series),
      left_join: i in assoc(is, :images),
      order_by: [asc: m.name, asc: is.sequence, asc: i.sequence],
      preload: [image_series: {is, images: i}]
  end

  @doc """
  Delete `category` from database

  Also delete all dependent image_series which in part deletes all
  dependent images.
  """
  def delete(category) do
    Brando.Images.Utils.delete_series_for(category_id: category.id)
    Brando.repo.delete!(category)
  end

  #
  # Meta

  use Brando.Meta.Model, [
    singular: gettext("image category"),
    plural: gettext("image categories"),
    repr: &("#{&1.name}"),
    fields: [
      id: gettext("ID"),
      name: gettext("Name"),
      slug: gettext("Slug"),
      cfg: gettext("Config"),
      creator: gettext("Creator"),
      image_series: gettext("Image series"),
      inserted_at: gettext("Inserted at"),
      updated_at: gettext("Updated at")
    ]
  ]
end
