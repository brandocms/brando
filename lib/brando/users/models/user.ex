defmodule Brando.Users.Model.User do
  @moduledoc """
  Ecto schema for the User model, as well as image field definitions
  and helper functions for dealing with the user model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  use Brando.Images.Field.ImageField
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils

  @required_fields ~w(username full_name email password)
  @optional_fields ~w(role avatar)

  @roles %{staff: 1, admin: 2, superuser: 4}

  def __name__(:singular), do: "bruker"
  def __name__(:plural), do: "brukere"

  def __str__(model) do
    "#{model.full_name} (#{model.username})"
  end

  use Linguist.Vocabulary
  locale "no", [
    model: [
      id: "ID",
      username: "Brukernavn",
      email: "Epost",
      full_name: "Navn",
      password: "Passord",
      avatar: "Avatar",
      creator: "Opprettet av",
      role: "Roller",
      last_login: "Siste innlogging",
      inserted_at: "Opprettet",
      updated_at: "Oppdatert"
    ]
  ]

  schema "users" do
    field :username, :string
    field :email, :string
    field :full_name, :string
    field :password, :string
    field :avatar, Brando.Type.Image
    field :role, Brando.Type.Role
    field :last_login, Ecto.DateTime
    timestamps
  end

  has_image_field :avatar,
    [allowed_mimetypes: ["image/jpeg", "image/png"],
     default_size: :medium,
     upload_path: Path.join("images", "avatars"),
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
  def changeset(model, action, params \\ nil)
  def changeset(model, :create, params) do
    params =
      params
      |> strip_unhandled_upload("avatar")

    model
    |> cast(params, @required_fields, @optional_fields)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/@/)
    |> validate_unique(:email, on: Brando.get_repo())
    |> validate_format(:username, ~r/^[a-z0-9_\-\.!~\*'\(\)]+$/)
    |> validate_length(:password, min: 6, too_short: "Passord må være > 6 tegn")
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
      |> strip_unhandled_upload("avatar")

    model
    |> cast(params, [], @required_fields ++ @optional_fields)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/@/)
    |> validate_unique(:email, on: Brando.get_repo())
    |> validate_format(:username, ~r/^[a-z0-9_\-\.!~\*'\(\)]+$/)
    |> validate_length(:password, min: 6, too_short: "Passord må være > 6 tegn")
  end

  @doc """
  Create a changeset for the user model by passing `params`.
  If valid, generate a hashed password and insert user to Repo.
  If not valid, return errors from changeset
  """
  def create(params) do
    user_changeset = changeset(%__MODULE__{}, :create, params)
    case user_changeset.valid? do
      true ->
        user_changeset = put_change(user_changeset, :password, gen_password(user_changeset.changes[:password]))
        inserted_user = Brando.get_repo().insert(user_changeset)
        {:ok, inserted_user}
      false ->
        {:error, user_changeset.errors}
    end
  end

  @doc """
  Create an `update` changeset for the user model by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update user in Repo.
  If not valid, return errors from changeset
  """
  def update(user, params) do
    user_changeset = changeset(user, :update, params)
    case user_changeset.valid? do
      true ->
        if Dict.has_key?(user_changeset.changes, :password) do
          user_changeset = put_change(user_changeset, :password, gen_password(user_changeset.changes[:password]))
        end
        {:ok, Brando.get_repo().update(user_changeset)}
      false ->
        {:error, user_changeset.errors}
    end
  end

  @doc """
  Get user from DB by `username`
  """
  def get(username: username) do
    from(u in __MODULE__,
         where: fragment("lower(?) = lower(?)", u.username, ^username),
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end

  @doc """
  Get user from DB by `email`
  """
  def get(email: email) do
    from(u in __MODULE__,
         where: fragment("? = lower(?)", u.email, ^email),
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    from(u in __MODULE__,
         where: u.id == ^id,
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end

  @doc """
  Get model by `val` or raise `Ecto.NoResultsError`.
  """
  def get!(val) do
    get(val) || raise Ecto.NoResultsError, queryable: __MODULE__
  end

  @doc """
  Delete `id` from database. Also deletes any connected image fields,
  including all generated sizes.
  """
  def delete(record) when is_map(record) do
    if record.avatar do
      delete_media(record.avatar.path)
      delete_connected_images(record.avatar.sizes)
    end
    Brando.get_repo.delete(record)
  end
  def delete(id) do
    record = get!(id)
    delete(record)
  end


  @doc """
  Get all users. Ordered by `id`
  """
  def all do
    q = from u in __MODULE__,
        order_by: u.id
    Brando.get_repo.all(q)
  end

  @doc """
  Bumps `user`'s `last_login` to current time.
  """
  @spec set_last_login(t) :: t
  def set_last_login(user) do
    {:ok, user} = Utils.Model.update_field(user, [last_login: Ecto.DateTime.local])
    user
  end

  @doc """
  Checks `password` against `user`. Return bool.
  """
  def auth?(nil, _password), do: false
  def auth?(user, password) do
    stored_hash = user.password
    password    = String.to_char_list(password)
    {:ok, hash} = :bcrypt.hashpw(password, stored_hash)
    hash        = :erlang.list_to_binary(hash)

    Utils.secure_compare(hash, stored_hash)
  end

  def gen_password(password) do
    password    = String.to_char_list(password)
    work_factor = 12
    {:ok, salt} = :bcrypt.gen_salt(work_factor)
    {:ok, hash} = :bcrypt.hashpw(password, salt)
    :erlang.list_to_binary(hash)
  end

  @doc """
  Checks if `user` has `role`.
  """
  @spec has_role?(t, atom) :: boolean
  def has_role?(user, role) when is_atom(role) do
    if role in user.role, do: true, else: false
  end

  @doc """
  Checks if `user` has access to admin area.
  """
  @spec can_login?(t) :: boolean
  def can_login?(user) do
    if user.role > 0, do: true, else: false
  end
end
