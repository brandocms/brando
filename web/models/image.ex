defmodule Brando.Image do
  @moduledoc """
  Ecto schema for the Image model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Images.Upload
  use Brando.Sequence, :model
  import Brando.Utils.Model, only: [put_creator: 2]
  import Ecto.Query, only: [from: 2]
  alias Brando.User
  alias Brando.ImageSeries

  @required_fields ~w(image image_series_id)
  @optional_fields ~w(sequence creator_id)

  schema "images" do
    field :image, Brando.Type.Image
    belongs_to :creator, User
    belongs_to :image_series, ImageSeries
    sequenced
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
  @spec changeset(t, atom, %{binary => term} | %{atom => term}) :: t
  def changeset(model, :update, params) do
    model
    |> cast(params, [], @required_fields ++ @optional_fields)
  end

  @doc """
  Create a changeset for the model by passing `params`.
  If valid, generate a hashed password and insert model to Brando.repo.
  If not valid, return errors from changeset
  """
  @spec update(%{binary => term} | %{atom => term}, User.t) :: {:ok, t} | {:error, Keyword.t}
  def create(params, current_user) do
    model_changeset =
      %__MODULE__{}
      |> put_creator(current_user)
      |> changeset(:create, params)
    case model_changeset.valid? do
      true  -> {:ok, Brando.repo.insert!(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  @doc """
  Create an `update` changeset for the model by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update model in Brando.repo.
  If not valid, return errors from changeset
  """
  @spec update(t, %{binary => term} | %{atom => term}) :: {:ok, t} | {:error, Keyword.t}
  def update(model, params) do
    model_changeset = model |> changeset(:update, params)
    case model_changeset.valid? do
      true ->  {:ok, Brando.repo.update!(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  @doc """
  Updates the `model`'s image JSON field with `title` and `credits`
  """
  def update_image_meta(model, title, credits) do
    image =
      model.image
      |> Map.put(:title, title)
      |> Map.put(:credits, credits)

    model_changeset = model |> changeset(:update, %{"image" => image})
    case model_changeset.valid? do
      true ->  {:ok, Brando.repo.update!(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  @doc """
  Get all images in series `id`.
  """
  def get_by_series_id(id) do
    from(m in __MODULE__,
         where: m.image_series_id == ^id,
         order_by: m.sequence)
    |> Brando.repo.all
  end

  @doc """
  Delete `record` from database

  Also deletes all dependent image sizes.
  """
  def delete(ids) when is_list(ids) do
    q = from(m in __MODULE__, where: m.id in ^ids)
    records = q |> Brando.repo.all
    for record <- records do
      record.image |> delete_original_and_sized_images
    end
    q |> Brando.repo.delete_all
  end

  def delete(record) when is_map(record) do
    record.image |> delete_original_and_sized_images
    Brando.repo.delete!(record)
  end

  def delete(id) do
    record = Brando.repo.get_by!(__MODULE__, id: id)
    delete(record)
  end

  @doc """
  Delete all images depending on imageserie `series_id`
  """
  def delete_dependent_images(series_id) do
    images =
      from(m in __MODULE__, where: m.image_series_id == ^series_id)
      |> Brando.repo.all

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