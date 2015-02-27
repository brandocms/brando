defmodule Brando.Images.Model.Image do
  @moduledoc """
  Ecto schema for the Image model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  use Brando.Images.Upload
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils
  alias Brando.Users.Model.User
  alias Brando.Images.Model.ImageSeries

  def __name__(:singular), do: "bilde"
  def __name__(:plural), do: "bilder"

  def __str__(model) do
    "#{model.id} | #{model.image}"
  end

  use Linguist.Vocabulary
  locale "no", [
    model: [
      id: "ID",
      title: "Tittel",
      credits: "Krediteringer",
      image: "Bilde",
      order: "Rekkefølge",
      optimized: "Optimisert",
      creator: "Opprettet av",
      image_series: "Bildeserie",
      inserted_at: "Opprettet",
      updated_at: "Oppdatert"
    ]
  ]

  schema "images" do
    field :title, :string
    field :credits, :string
    field :image, :string
    field :order, :integer
    field :optimized, :boolean
    belongs_to :creator, User
    belongs_to :image_series, ImageSeries
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
    params
    |> cast(model, ~w(image image_series_id), ~w(title credits order optimized creator_id))
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :update.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :update, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :update, params) do
    params
    |> cast(model, [], ~w(image image_series_id title credits order optimized creator_id))
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

  def get(id: id) do
    from(m in __MODULE__,
         where: m.id == ^id,
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end
end