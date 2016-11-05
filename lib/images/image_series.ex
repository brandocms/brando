defmodule Brando.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series schema
  and helper functions for dealing with the schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Sequence, :schema

  alias Brando.ImageCategory

  import Ecto.Query, only: [from: 2]
  import Brando.Utils.Schema, only: [avoid_slug_collision: 1]
  import Brando.Gettext

  @required_fields ~w(name slug image_category_id creator_id)a
  @optional_fields ~w(credits sequence cfg)a

  schema "imageseries" do
    field :name, :string
    field :slug, :string
    field :credits, :string
    field :cfg, Brando.Type.ImageConfig
    belongs_to :creator, Brando.User
    belongs_to :image_category, Brando.ImageCategory
    has_many :images, Brando.Image
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
  def changeset(schema, action, params \\ %{})
  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:slug)
    |> avoid_slug_collision
    |> inherit_configuration
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid
  changeset when action is :update.

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :update, params)

  """
  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> unique_constraint(:slug)
    |> avoid_slug_collision
    |> validate_paths
  end

  @doc """
  Get all imageseries in category `id`.
  """
  @spec by_category_id(integer) :: Ecto.Queryable.t
  def by_category_id(id) do
    from m in __MODULE__,
         where: m.image_category_id == ^id,
      order_by: m.sequence,
       preload: [:images]
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

  defp do_inherit_configuration(cs, cat_id, nil) do
    category = Brando.repo.get(ImageCategory, cat_id)
    cfg      = category.cfg

    put_change(cs, :cfg, cfg)
  end

  defp do_inherit_configuration(cs, cat_id, slug) do
    category        = Brando.repo.get(ImageCategory, cat_id)
    new_upload_path = Path.join(Map.get(category.cfg, :upload_path), slug)
    cfg             = Map.put(category.cfg, :upload_path, new_upload_path)

    put_change(cs, :cfg, cfg)
  end

  @doc """
  Checks if slug was changed in changeset.

  If it is, move and fix paths/files + redo thumbs
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

  use Brando.Meta.Schema, [
    singular: gettext("imageserie"),
    plural: gettext("imageseries"),
    repr: fn (schema) ->
       schema = Brando.repo.preload(schema, :images)
       image_count = Enum.count(schema.images)
       "#{schema.name} – #{image_count} #{gettext("image(s)")}."
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
