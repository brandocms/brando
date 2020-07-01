defmodule Brando.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series schema
  and helper functions for dealing with the schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Sequence.Schema
  use Brando.SoftDelete.Schema

  alias Brando.ImageCategory

  import Ecto.Query, only: [from: 2]

  @required_fields ~w(name image_category_id creator_id)a
  @optional_fields ~w(credits sequence cfg slug deleted_at)a

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :slug,
             :credits,
             :cfg,
             :creator,
             :creator_id,
             :image_category_id,
             :image_category,
             :images,
             :sequence,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}

  schema "images_series" do
    field :name, :string
    field :slug, :string
    field :credits, :string
    field :cfg, Brando.Type.ImageConfig
    belongs_to :creator, Brando.Users.User
    belongs_to :image_category, Brando.ImageCategory
    has_many :images, Brando.Image
    sequenced()
    timestamps()
    soft_delete()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, params)

  """
  @spec changeset(t, Map.t()) :: Ecto.Changeset.t()
  def changeset(schema, params \\ %{}, user \\ :system) do
    cs =
      schema
      |> cast(params, @required_fields ++ @optional_fields)
      |> put_creator(user)
      |> validate_required(@required_fields)
      |> put_slug(:name)
      |> avoid_slug_collision(&filter_current_category/1)
      |> inherit_configuration()

    cs
    |> cast_assoc(:images, with: {Brando.Image, :changeset, [user, get_field(cs, :cfg)]})
    |> validate_paths()
  end

  @doc """
  Filter used in `avoid_slug_collision` to ensure we are only checking slugs
  from the same category.
  """
  def filter_current_category(cs) do
    from m in __MODULE__,
      where: m.image_category_id == ^get_field(cs, :image_category_id)
  end

  @doc """
  Get all imageseries in category `id`.
  """
  @spec by_category_id(integer) :: Ecto.Queryable.t()
  def by_category_id(id) do
    from m in __MODULE__,
      where: m.image_category_id == ^id,
      order_by: m.sequence,
      preload: [:images]
  end

  @doc """
  Before inserting changeset. Copies the series' category config.
  """
  def inherit_configuration(%{valid?: true} = cs) do
    case get_change(cs, :cfg) do
      nil ->
        cat_id = get_field(cs, :image_category_id)

        if !cat_id do
          raise "inherit_configuration => image_category_id === nil!"
        end

        slug = get_change(cs, :slug)

        if slug do
          category = Brando.repo().get(ImageCategory, cat_id)
          new_upload_path = Path.join(Map.get(category.cfg, :upload_path), slug)
          cfg = Map.put(category.cfg, :upload_path, new_upload_path)
          put_change(cs, :cfg, cfg)
        else
          cs
        end

      _ ->
        cs
    end
  end

  def inherit_configuration(cs) do
    cs
  end

  @doc """
  Checks if slug was changed in changeset.

  If it is, move and fix paths/files + redo thumbs
  """
  def validate_paths(%Ecto.Changeset{valid?: true, data: %{id: id}} = cs) when not is_nil(id) do
    slug = get_change(cs, :slug)

    if slug do
      cfg = cs.data.cfg
      split_path = Path.split(cfg.upload_path)

      new_path =
        split_path
        |> List.delete_at(Enum.count(split_path) - 1)
        |> Path.join()
        |> Path.join(slug)

      cfg = Map.put(cfg, :upload_path, new_path)
      put_change(cs, :cfg, cfg)
    else
      cs
    end
  end

  def validate_paths(cs), do: cs
end
