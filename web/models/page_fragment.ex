defmodule Brando.PageFragment do
  @moduledoc """
  Ecto schema for the PageFragment model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  import Brando.Utils.Model, only: [put_creator: 2]
  import Ecto.Query, only: [from: 2]
  alias Brando.Type.Json
  alias Brando.User

  @required_fields ~w(key language data creator_id)
  @optional_fields ~w()

  schema "pagefragments" do
    field :key, :string
    field :language, :string
    field :data, Json
    field :html, :string
    belongs_to :creator, User
    timestamps
  end

  before_insert :generate_html
  before_update :generate_html

  @doc """
  Callback from before_insert/before_update to generate HTML.
  Takes the model's `json` field and transforms to `html`.
  """

  def generate_html(changeset) do
    if get_change(changeset, :data) do
      changeset |> put_change(:html, Brando.Villain.parse(changeset.changes.data))
    else
      changeset
    end
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
    case model_changeset.valid? do
      true  -> {:ok, Brando.repo.insert(model_changeset)}
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
      true  -> {:ok, Brando.repo.update(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  def encode_data(params) do
    cond do
      is_list(params.data)   -> Map.put(params, :data, Poison.encode!(params.data))
      is_binary(params.data) -> params
    end
  end

  @doc """
  Delete `id` from database. Also deletes any connected image fields,
  including all generated sizes.
  """
  def delete(record) when is_map(record) do
    Brando.repo.delete(record)
  end
  def delete(id) do
    record = Brando.repo.get_by(__MODULE__, id: id)
    delete(record)
  end

  @doc """
  Get all records. Ordered by `id`. Preload :creator.
  """
  def all do
    (from m in __MODULE__,
          order_by: [desc: m.inserted_at],
          preload: [:creator])
    |> Brando.repo.all
  end


  #
  # Meta

  use Brando.Meta, [
    singular: "sidefragment",
    plural: "sidefragmenter",
    repr: &("#{&1.key}"),
    fields: [
       id: "№",
       language: "Språk",
       key: "Id-nøkkel",
       data: "Data",
       html: "HTML",
       creator: "Opprettet av",
       inserted_at: "Opprettet",
       updated_at: "Oppdatert"]]
end