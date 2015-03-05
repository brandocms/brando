defmodule Brando.News.Model.Post do
  @moduledoc """
  Ecto schema for the Post model, as well as image field definitions
  and helper functions for dealing with the post model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  use Brando.Images.Field.ImageField
  import Ecto.Query, only: [from: 2]
  alias Brando.Type.Json
  alias Brando.Type.Status
  alias Brando.Users.Model.User
  alias Brando.Utils

  schema "posts" do
    field :language, :string
    field :header, :string
    field :slug, :string
    field :lead, :string
    field :data, Json
    field :html, :string
    field :cover, :string
    field :status, Status
    belongs_to :creator, User
    field :meta_description, :string
    field :meta_keywords, :string
    field :featured, :boolean
    field :published, :boolean
    field :publish_at, Ecto.DateTime
    timestamps
  end

  before_insert :generate_html
  before_update :generate_html

  has_image_field :cover,
    [allowed_mimetypes: ["image/jpeg", "image/png"],
     default_size: :medium,
     upload_path: Path.join(["images", "posts", "covers"]),
     random_filename: true,
     size_limit: 10240000,
     sizes: [
       small:  [size: "300", quality: 100],
       medium: [size: "500", quality: 100],
       large:  [size: "700", quality: 100],
       xlarge: [size: "900", quality: 100],
       thumb:  [size: "150x150^ -gravity center -extent 150x150", quality: 100, crop: true]
    ]
  ]

  @doc """
  Callback from before_insert/before_update to generate HTML.
  Takes the model's `json` field and transforms to `html`.
  """

  def generate_html(changeset) do
    changeset |> put_change(:html, Villain.parse(changeset.changes.data))
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :create, params) do
    params =
      params
      |> encode_data
      |> strip_unhandled_upload("cover")
      |> Utils.Model.transform_checkbox_vals(~w(featured))

    model
    |> cast(params, ~w(status header data lead creator_id language), ~w(featured))
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :update.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :update, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :update, params) do
    params =
      params
      |> encode_data
      |> strip_unhandled_upload("cover")
      |> Utils.Model.transform_checkbox_vals(~w(featured))

    model
    |> cast(params, [], ~w(status header data lead creator_id featured language))
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

  defp encode_data(params), do:
    Map.put(params, "data", Poison.decode!(params["data"]))

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    from(m in __MODULE__,
         where: m.id == ^id,
         preload: [:creator],
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end

  @doc """
  Delete `model` from database. Also deletes any connected image fields,
  including all generated sizes.
  """
  def delete(model) do
    Brando.get_repo.delete(model)
    delete_connected_images(model, @imagefields)
  end

  @doc """
  Get all posts. Ordered by `id`. Preload :creator.
  """
  def all do
    q = from m in __MODULE__,
        order_by: [asc: m.status, desc: m.inserted_at],
        preload: [:creator]
    Brando.get_repo.all(q)
  end
end