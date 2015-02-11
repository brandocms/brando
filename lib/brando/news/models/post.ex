defmodule Brando.News.Model.Post do
  @moduledoc """
  Ecto schema for the Post model, as well as image field definitions
  and helper functions for dealing with the post model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  use Brando.Mugshots.Fields.ImageField
  import Ecto.Query, only: [from: 2]
  alias Brando.Util
  alias Brando.Type.Status
  alias Brando.Users.Model.User

  schema "posts" do
    field :language, :string
    field :header, :string
    field :slug, :string
    field :lead, :string
    field :data, :string
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
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :create, params) do
    params
    |> transform_checkbox_vals(~w(featured))
    |> cast(model, ~w(status header data lead creator_id language), ~w(featured))
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
    |> transform_checkbox_vals(~w(featured))
    |> cast(model, [], ~w(status header data lead creator_id featured language))
  end

  @doc """
  Create a changeset for the model by passing `params`.
  If valid, generate a hashed password and insert model to Repo.
  If not valid, return errors from changeset
  """
  def create(params, current_user) do
    params = put_creator(params, current_user)
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

  Also updates the affected fields in the database if `handle_upload`
  returns {:ok, file_url}
  """
  def check_for_uploads(model, form_fields) do
    form_fields = Enum.filter(form_fields, fn (form_field) ->
      case form_field do
        {_, %Plug.Upload{}} -> true
        {_, _} -> false
      end
    end)

    dict = Enum.reduce(form_fields, [], fn {field_name, plug}, dict ->
      cfg = get_image_cfg(String.to_atom(field_name))
      case handle_upload(plug, cfg) do
        {:ok, file_url} ->
          apply(__MODULE__, :update_field, [model, Keyword.new([{String.to_atom(field_name), file_url}])])
          [file: {String.to_atom(field_name), file_url}] ++ dict
        {:error, error} ->
          [error: {String.to_atom(field_name), error}] ++ dict
      end
    end)
    case dict do
      [] -> :nouploads
      dict ->
        case Dict.has_key?(dict, :error) do
          true -> {:errors, dict}
          false -> {:ok, dict}
        end
    end
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
  Checkbox values from forms come with value => "on". This transforms
  them into bool values if params[key] is in keys.

  # Example:

      transform_checkbox_vals(params, ~w(administrator editor))

  """
  def transform_checkbox_vals(params, keys) do
    Enum.into(Enum.map(params, fn({k, v}) ->
      case k in keys and v == "on" do
        true  -> {k, true}
        false -> {k, v}
      end
    end), %{})
  end

  @doc """
  Puts `id` from `current_user` in the `params` map.
  """
  def put_creator(params, current_user), do:
    Map.put(params, "creator_id", current_user.id)

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
        order_by: [asc: m.status, desc: m.inserted_at],
        preload: [:creator]
    Brando.get_repo.all(q)
  end
end