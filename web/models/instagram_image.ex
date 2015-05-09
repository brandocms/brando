defmodule Brando.InstagramImage do
  @moduledoc """
  Ecto schema for the InstagramImage model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  require Logger
  import Ecto.Query, only: [from: 2]

  @cfg Application.get_env(:brando, Brando.Instagram)

  @required_fields ~w(instagram_id caption link url_original username
                      url_thumbnail created_time type approved deleted)
  @optional_fields ~w()

  schema "instagramimages" do
    field :instagram_id, :string
    field :type, :string
    field :caption, :string
    field :link, :string
    field :username, :string
    field :url_original, :string
    field :url_thumbnail, :string
    field :created_time, :string
    field :approved, :boolean, default: false
    field :deleted, :boolean, default: false
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
    |> validate_unique(:instagram_id, on: Brando.repo)
    |> put_change(:approved, @cfg[:auto_approve])
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
  If not valid, return errors from changeset
  """
  @spec create(%{binary => term} | %{atom => term}) :: {:ok, t} | {:error, Keyword.t}
  def create(params) do
    model_changeset = %__MODULE__{} |> changeset(:create, params)
    case model_changeset.valid? do
      true ->  {:ok, Brando.repo.insert(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  @doc """
  Create an `update` changeset for the model by passing `params`.
  If valid, update model in Brando.repo.
  If not valid, return errors from changeset
  """
  @spec update(t, %{binary => term} | %{atom => term}) :: {:ok, t} | {:error, Keyword.t}
  def update(model, params) do
    model_changeset = model |> changeset(:update, params)
    case model_changeset.valid? do
      true ->  {:ok, Brando.repo.update(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  @doc """
  Takes a map provided from the API and transforms it to a map we can
  use to store in the DB.
  """
  def store_image(%{"id" => instagram_id, "caption" => caption, "user" => user,
                    "images" => %{"thumbnail" => %{"url" => thumb},
                                  "standard_resolution" => %{"url" => org}}} = image) do
    image
    |> Map.drop(["images", "id"])
    |> Map.put("username", user["username"])
    |> Map.put("instagram_id", instagram_id)
    |> Map.put("caption", (if caption, do: caption["text"], else: ""))
    |> Map.put("url_thumbnail", thumb)
    |> Map.put("url_original", org)
    |> create
  end

  @doc """
  Get timestamp from where we search for new images
  """
  def get_last_created_time do
    max =
      from(m in __MODULE__,
           select: m.created_time,
           order_by: [desc: m.created_time],
           limit: 1)
      |> Brando.repo.one
    case max do
      nil -> ""
      max -> max
             |> String.to_integer
             |> Kernel.+(1)
             |> Integer.to_string
    end
  end

  @doc """
  Get min_id from where we search for new images
  """
  def get_min_id do
    id =
      from(m in __MODULE__,
           select: m.instagram_id,
           order_by: [desc: m.instagram_id],
           limit: 1)
      |> Brando.repo.one
    case id do
      nil -> ""
      id -> Enum.at(String.split(id, "_"), 0)
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
    from(m in __MODULE__, where: m.id == ^id)
    |> Brando.repo.one
  end

  @doc """
  Get all results
  """
  def all do
    from(m in __MODULE__, order_by: m.instagram_id)
    |> Brando.repo.all
  end
  @doc """
  Delete `record` from database

  Also deletes all dependent image sizes.
  """
  def delete(ids) when is_list(ids) do
    for id <- ids, do:
      delete(id)
  end

  def delete(record) when is_map(record) do
    Brando.repo.delete(record)
  end

  def delete(id) do
    record = get!(id: id)
    delete(record)
  end

  #
  # Meta

  use Brando.Meta,
    [singular: "instagrambilde",
     plural: "instagrambilder",
     repr: &("#{&1.id} | #{&1.image.path}"),
     fields: [id: "ID",
              instagram_id: "Instagram ID",
              type: "Type",
              caption: "Tittel",
              link: "Link",
              url_original: "Bilde-URL",
              url_thumbnail: "Miniatyrbilde-URL",
              created_time: "Opprettet",
              approved: "Godkjent til bruk",
              deleted: "Merket som slettet"]]

end