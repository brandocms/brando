defmodule Brando.Image do
  @moduledoc """
  Ecto schema for the Image model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Images.Upload
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils
  alias Brando.User
  alias Brando.ImageSeries

  @required_fields ~w(image image_series_id)
  @optional_fields ~w(order creator_id)

  schema "images" do
    field :image, Brando.Type.Image
    field :order, :integer
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
  If valid, generate a hashed password and insert model to Brando.get_repo().
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
  If valid, update model in Brando.get_repo().
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

  def update_image_meta(model, title, credits) do
    image =
      model.image
      |> Map.put(:title, title)
      |> Map.put(:credits, credits)

    model_changeset = changeset(model, :update, %{"image" => image})
    case model_changeset.valid? do
      true ->
        {:ok, Brando.get_repo().update(model_changeset)}
      false ->
        {:error, model_changeset.errors}
    end
  end

  @doc """
  Get model by `val` or raise `Ecto.NoResultsError`.
  """
  def get!(val) do
    get(val) || raise Ecto.NoResultsError, queryable: __MODULE__
  end

  @doc """
  Get model by `id: id`.
  """
  def get(id: id) do
    from(m in __MODULE__,
         where: m.id == ^id)
    |> Brando.get_repo.one
  end

  @doc """
  Reorder image order field.

  ## Example:

      reorder_images(["1", "2", "3"], ["3", "2", "1"]")

  """
  def reorder_images(ids, vals) do
    order = Enum.zip(vals, ids)
    Brando.get_repo.transaction(fn -> Enum.map(order, fn ({val, id}) ->
      Ecto.Adapters.SQL.query(Brando.get_repo, "UPDATE images SET \"order\" = $1 WHERE \"id\" = $2", [val, String.to_integer(id)])
    end) end)
  end

  @doc """
  Delete `record` from database

  Also deletes all dependent image sizes.
  """
  def delete(ids) when is_list(ids) do
    for id <- ids do
      delete(id)
    end
  end

  def delete(record) when is_map(record) do
    if record.image do
      delete_media(record.image.path)
      delete_connected_images(record.image.sizes)
    end
    Brando.get_repo.delete(record)
  end
  def delete(id) do
    record = get!(id: id)
    delete(record)
  end

  @doc """
  Delete all images depending on imageserie `series_id`
  """
  def delete_dependent_images(series_id) do
    images =
      from(m in __MODULE__, where: m.image_series_id == ^series_id)
      |> Brando.get_repo.all

    for img <- images do
      delete(img)
    end
  end

  #
  # Meta

  use Brando.Meta,
    [singular: "bilde",
     plural: "bilder",
     repr: &("#{&1.id} | #{&1.image.path}"),
     fields: [id: "ID",
              image: "Bilde",
              order: "Rekkefølge",
              creator: "Opprettet av",
              image_series: "Bildeserie",
              inserted_at: "Opprettet",
              updated_at: "Oppdatert"]]

end