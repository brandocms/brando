defmodule Brando.News.Model.PostImage do
  @moduledoc """
  Ecto schema for the PostImage model, as well as image field definitions
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  use Brando.Mugshots.Fields.ImageField
  import Ecto.Query, only: [from: 2]

  schema "postimages" do
    field :title, :string
    field :credits, :string
    field :image, :string
    timestamps
  end

  has_image_field :image,
    [allowed_mimetypes: ["image/jpeg", "image/png"],
     default_size: :medium,
     upload_path: Path.join(["images", "posts", "images"]),
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
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :create, params) do
    params
    |> strip_unhandled_upload("image")
    |> cast(model, ~w(), ~w(title credits image))
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
    |> strip_unhandled_upload("image")
    |> cast(model, [], ~w(title credits image))
  end

  @doc """
  Create a changeset for the model by passing `params`.
  If valid, generate a hashed password and insert model to Repo.
  If not valid, return errors from changeset
  """
  def create(params) do
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
  Checks `form_fields` for Plug.Upload fields and passes them on to
  `handle_upload` to check if we have a handler for the field.
  Returns {:ok, model} or raises
  """
  def check_for_uploads(model, params) do
    params
    |> filter_plugs
    |> Enum.reduce([], &handle_upload(&1, &2, model, __MODULE__, @imagefields))
  end

  @doc """
  Updates a field on `model`.
  `coll` should be [field_name: value]

  ## Example:

      {:ok, model} = update_field(model, [field_name: "value"])

  """
  def update_field(model, coll) do
    changeset = change(model, coll)
    {:ok, Brando.get_repo.update(changeset)}
  end

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    from(m in __MODULE__,
         where: m.id == ^id,
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
        order_by: [asc: m.title, desc: m.inserted_at]
    Brando.get_repo.all(q)
  end
end