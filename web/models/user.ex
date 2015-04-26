defmodule Brando.User do
  @moduledoc """
  Ecto schema for the User model, as well as image field definitions
  and helper functions for dealing with the user model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Field.ImageField
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils

  @required_fields ~w(username full_name email password)
  @optional_fields ~w(role avatar)

  @roles Application.get_env(:brando, Brando.Type.Role) |> Keyword.get(:roles)

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
    model
    |> cast(params, @required_fields, @optional_fields)
    |> validate_format(:email, ~r/@/)
    |> validate_unique(:email, on: Brando.repo)
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
    model
    |> cast(params, [], @required_fields ++ @optional_fields)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/@/)
    |> validate_unique(:email, on: Brando.repo)
    |> validate_format(:username, ~r/^[a-z0-9_\-\.!~\*'\(\)]+$/)
    |> validate_length(:password, min: 6, too_short: "Passord må være > 6 tegn")
  end

  @doc """
  Create a changeset for the user model by passing `params`.
  If valid, generate a hashed password and insert user to Brando.repo.
  If not valid, return errors from changeset
  """
  def create(params) do
    user_changeset = changeset(%__MODULE__{}, :create, params)
    case user_changeset.valid? do
      true ->
        user_changeset = put_change(user_changeset, :password, gen_password(user_changeset.changes[:password]))
        inserted_user = Brando.repo.insert(user_changeset)
        {:ok, inserted_user}
      false ->
        {:error, user_changeset.errors}
    end
  end

  @doc """
  Create an `update` changeset for the user model by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update user in Brando.repo.
  If not valid, return errors from changeset
  """
  def update(user, params) do
    user_changeset = changeset(user, :update, params)
    case user_changeset.valid? do
      true ->
        if (Map.get(user, :password) != Map.get(user_changeset.changes, :password) &&
            Map.get(user_changeset.changes, :password) != nil) do
          user_changeset = put_change(user_changeset, :password, gen_password(user_changeset.changes[:password]))
        end
        {:ok, Brando.repo.update(user_changeset)}
      false ->
        {:error, user_changeset.errors}
    end
  end

  @doc """
  Get user from DB by `username`
  """
  def get(username: username) do
    from(u in __MODULE__,
         where: fragment("lower(?) = lower(?)", u.username, ^username))
    |> Brando.repo.one
  end

  @doc """
  Get user from DB by `email`
  """
  def get(email: email) do
    from(u in __MODULE__,
         where: fragment("? = lower(?)", u.email, ^email))
    |> Brando.repo.one
  end

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    from(u in __MODULE__,
         where: u.id == ^id)
    |> Brando.repo.one
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
    Brando.repo.delete(record)
  end
  def delete(id) do
    record = get!(id: id)
    delete(record)
  end


  @doc """
  Get all users. Ordered by `id`
  """
  def all do
    q = from u in __MODULE__,
        order_by: u.id
    Brando.repo.all(q)
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
    Comeonin.Bcrypt.checkpw(password, user.password)
  end

  @doc """
  Hashes `password` using Comeonin.Bcrypt
  """
  @spec gen_password(String.t) :: String.t
  def gen_password(password), do:
    Comeonin.Bcrypt.hashpwsalt(password, 12)

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

  #
  # Meta

  use Brando.Meta,
    [singular: "bruker",
     plural: "brukere",
     repr: &("#{&1.full_name} (#{&1.username})"),
     fields: [id: "ID",
              username: "Brukernavn",
              email: "Epost",
              full_name: "Navn",
              password: "Passord",
              role: "Roller",
              last_login: "Siste innlogging",
              inserted_at: "Opprettet",
              updated_at: "Oppdatert",
              avatar: "Avatar"],
     hidden_fields: [:password, :creator]]
end
