defmodule Brando.Images.Model.ImageCategory do
  @moduledoc """
  Ecto schema for the Image Category model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils
  alias Brando.Users.Model.User
  alias Brando.Images.Model.ImageSeries

  @required_fields ~w(name slug creator_id)
  @optional_fields ~w(cfg)

  def __name__(:singular), do: "bildekategori"
  def __name__(:plural), do: "bildekategorier"

  def __str__(model) do
    "#{model.name}"
  end

  use Linguist.Vocabulary
  locale "no", [
    model: [
      id: "ID",
      name: "Navn",
      slug: "URL-tamp",
      cfg: "Konfigurasjon",
      creator: "Opprettet av",
      image_series: "Bildeserie",
      inserted_at: "Opprettet",
      updated_at: "Oppdatert"
    ]
  ]

  schema "imagecategories" do
    field :name, :string
    field :slug, :string
    field :cfg,  :string
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

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    from(m in __MODULE__,
         where: m.id == ^id,
         preload: [:creator, :image_series],
         limit: 1)
    |> Brando.get_repo.one!
  end

  @doc """
  Get model by `val` or raise `Ecto.NoResultsError`.
  """
  def get!(val) do
    get(val) || raise Ecto.NoResultsError, queryable: __MODULE__
  end

  @doc """
  Get all records. Ordered by `id`.
  """
  def all do
    q = from m in __MODULE__,
        order_by: [asc: m.name],
        preload: [:image_series, image_series: :images]
    Brando.get_repo.all(q)
  end

  @doc """
  Delete `record` from database

  Also delete all dependent image_series which in part deletes all
  dependent images.
  """
  def delete(record) do
    Brando.Images.Model.ImageSeries.delete_dependent_image_series(record.id)
    Brando.get_repo.delete(record)
  end
end