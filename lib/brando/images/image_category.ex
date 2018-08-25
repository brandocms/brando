defmodule Brando.ImageCategory do
  @moduledoc """
  Ecto schema for the Image Category schema
  and helper functions for dealing with the schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema

  import Brando.Gettext
  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset

  @required_fields ~w(name creator_id)a
  @optional_fields ~w(cfg slug)a

  schema "imagecategories" do
    field :name, :string
    field :slug, :string
    field :cfg, Brando.Type.ImageConfig
    belongs_to :creator, Brando.User
    has_many :image_series, Brando.ImageSeries
    timestamps()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid
  changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, :create | :update, Keyword.t) :: t
  def changeset(schema, action, params \\ %{})
  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> put_slug(:name)
    |> avoid_slug_collision()
    |> unique_constraint(:slug)
    |> put_default_config
  end

  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_slug(:name)
    |> avoid_slug_collision()
    |> unique_constraint(:slug)
    |> validate_paths
  end

  @doc """
  Put default image config in changeset
  """
  @spec put_default_config(Ecto.Changeset.t) :: Ecto.Changeset.t
  def put_default_config(cs) do
    if get_change(cs, :cfg, nil) do
      cs
    else
      path_from_slug = get_change(cs, :slug, "default")
      upload_path    = Path.join(["images", "site", path_from_slug])
      default_config = Brando.Images
                       |> Brando.config
                       |> Keyword.get(:default_config)
                       |> Map.put(:upload_path, upload_path)

      put_change(cs, :cfg, default_config)
    end
  end

  @doc """
  Get all records. Ordered by `id`.
  """
  @spec with_image_series_and_images(Ecto.Queryable.t) :: Ecto.Queryable.t
  def with_image_series_and_images(query) do
    from m in query,
      left_join: is in assoc(m, :image_series),
      left_join: i in assoc(is, :images),
       order_by: [asc: m.inserted_at, asc: is.sequence, asc: i.sequence],
        preload: [image_series: {is, images: i}]
  end

  @doc """
  Validate `cs` cfg upload_path if slug is changed
  """
  @spec validate_paths(Ecto.Changeset.t) :: Ecto.Changeset.t
  def validate_paths(%Ecto.Changeset{changes: %{slug: slug}} = cs) do
    old_cfg    = cs.data.cfg
    split_path = Path.split(old_cfg.upload_path)
    new_path   = split_path
                 |> List.delete_at(Enum.count(split_path) - 1)
                 |> Path.join
                 |> Path.join(slug)

    new_cfg    = Map.put(old_cfg, :upload_path, new_path)

    put_change(cs, :cfg, new_cfg)
  end

  def validate_paths(cs), do: cs

  #
  # Meta

  use Brando.Meta.Schema, [
    singular: gettext("image category"),
    plural: gettext("image categories"),
    repr: &(&1.name),
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
