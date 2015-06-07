defmodule Brando.ImageCategory do
  @moduledoc """
  Ecto schema for the Image Category model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  import Brando.Utils.Model, only: [put_creator: 2]
  import Ecto.Query, only: [from: 2]
  alias Brando.User
  alias Brando.ImageSeries

  @required_fields ~w(name slug creator_id)
  @optional_fields ~w(cfg)

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
      |> put_change(:cfg, Brando.config(Brando.Images)[:default_config])

    case model_changeset.valid? do
      true ->  {:ok, Brando.repo.insert(model_changeset)}
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

  @doc """
  Returns the model's slug
  """
  def get_slug(id: id) do
    from(m in __MODULE__,
      select: m.slug,
      where: m.id == ^id)
      |> Brando.repo.one!
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
  Delete `record` from database

  Also delete all dependent image_series which in part deletes all
  dependent images.
  """
  def delete(record) do
    Brando.ImageSeries.delete_dependent_image_series(record.id)
    Brando.repo.delete(record)
  end

  #
  # Meta

  use Brando.Meta,
    [singular: "bildekategori",
     plural: "bildekategorier",
     repr: &("#{&1.name}"),
     fields: [id: "ID",
              name: "Navn",
              slug: "URL-tamp",
              cfg: "Konfigurasjon",
              creator: "Opprettet av",
              image_series: "Bildeserie",
              inserted_at: "Opprettet",
              updated_at: "Oppdatert"]]
end