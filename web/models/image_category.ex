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
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:slug)
    |> put_default_config
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
    |> cast(params, @required_fields ++ @optional_fields)
    |> unique_constraint(:slug)
    |> validate_paths()
  end

  @doc """
  Put default image config in changeset
  """
  def put_default_config(cs) do
    path = Ecto.Changeset.get_change(cs, :slug, "default")
    default_config =
      Brando.config(Brando.Images)[:default_config]
      |> Map.put(:upload_path, Path.join(["images", "site", path]))

    put_change(cs, :cfg, default_config)
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
  Validate `cs` cfg upload_path if slug is changed
  """
  def validate_paths(cs) do
    slug = get_change(cs, :slug)
    if slug do
      cfg = cs.data.cfg
      split_path = Path.split(cfg.upload_path)

      new_path =
        split_path
        |> List.delete_at(Enum.count(split_path) - 1)
        |> Path.join
        |> Path.join(slug)

      cfg = Map.put(cfg, :upload_path, new_path)
      put_change(cs, :cfg, cfg)
    else
      cs
    end
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
