defmodule Brando.PageFragment do
  @moduledoc """
  Ecto schema for the PageFragment model.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Villain, :model

  alias Brando.Type.Json
  alias Brando.User

  import Brando.Gettext
  import Brando.Utils.Model, only: [put_creator: 2]

  @required_fields ~w(key language data creator_id)
  @optional_fields ~w(html)

  schema "pagefragments" do
    field :key, :string
    field :language, :string
    field :data, Json
    field :html, :string
    belongs_to :creator, User
    timestamps
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t | :empty) :: t
  def changeset(model, action, params \\ :empty)
  def changeset(model, :create, params) do
    model
    |> cast(params, @required_fields, @optional_fields)
    |> generate_html()
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
    |> generate_html()
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

  def encode_data(params) do
    cond do
      is_list(params.data)   ->
        Map.put(params, :data, Poison.encode!(params.data))
      is_binary(params.data) ->
        params
    end
  end

  @doc """
  Delete `id` from database. Also deletes any connected image fields,
  including all generated sizes.
  """
  def delete(record) when is_map(record) do
    Brando.repo.delete!(record)
  end
  def delete(id) do
    __MODULE__
    |> Brando.repo.get_by!(id: id)
    |> delete
  end

  @doc """
  Get all records. Ordered by `id`. Preload :creator.
  """
  def all do
    Brando.repo.all(
      from m in __MODULE__,
        order_by: [desc: m.inserted_at],
        preload: [:creator]
    )
  end


  #
  # Meta

  use Brando.Meta.Model, [
    singular: gettext("page fragment"),
    plural: gettext("page fragments"),
    repr: &("#{&1.key}"),
    fields: [
      id: "№",
      language: gettext("Language"),
      key: gettext("Key"),
      data: gettext("Data"),
      html: gettext("HTML"),
      creator: gettext("Creator"),
      inserted_at: gettext("Inserted"),
      updated_at: gettext("Updated")
    ]
  ]
end
