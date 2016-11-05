defmodule Brando.User do
  @moduledoc """
  Ecto schema for the User schema, as well as image field definitions
  and helper functions for dealing with the user schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Field.ImageField

  import Brando.Gettext

  @required_fields ~w(username full_name email password language)a
  @optional_fields ~w(role avatar)a

  @forbidden_usernames ~w(
    admin
    superadmin
    superuser
    editor
    root
    create
    edit
    delete
    update
    ny
    endre
    slett
    profil
  )

  schema "users" do
    field :username, :string
    field :email, :string
    field :full_name, :string
    field :password, :string
    field :avatar, Brando.Type.Image
    field :role, Brando.Type.Role
    field :language, :string
    field :last_login, :naive_datetime
    timestamps
  end

  has_image_field :avatar, %{
    allowed_mimetypes: [
      "image/jpeg",
      "image/png",
      "image/gif"
    ],
    default_size: :medium,
    upload_path: Path.join("images", "avatars"),
    random_filename: true,
    size_limit: 10240000,
    sizes: %{
      "micro"  => %{
        "size"    => "25x25",
        "quality" => 100,
        "crop"    => true
      },
      "thumb"  => %{
        "size"    => "150x150",
        "quality" => 100,
        "crop"    => true
      },
      "small"  => %{
        "size"    => "300",
        "quality" => 100
      },
      "medium" => %{
        "size"    => "500",
        "quality" => 100
      },
      "large"  => %{
        "size"    => "700",
        "quality" => 100
      },
      "xlarge" => %{
        "size"    => "900",
        "quality" => 100
     }
    },
    srcset: %{
      "small"  => "300w",
      "medium" => "500w",
      "large"  => "700w"
    }
  }

  @doc """
  Casts and validates `params` against `schema` to create a valid
  changeset when action is :create.

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, :create | :update, %{binary => term} | %{atom => term}) :: t
  def changeset(schema, action, params \\ %{})
  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> validate_format(:username, ~r/^[a-z0-9_\-\.!~\*'\(\)]+$/)
    |> validate_exclusion(:username, @forbidden_usernames)
    |> validate_confirmation(:password, message: gettext("Passwords must match"))
    |> validate_length(:password, min: 6, too_short: gettext("Password must be at least 6 characters"))
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid
  changeset when action is :update.

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :update, params)

  """
  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> cleanup_old_images()
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> validate_format(:username, ~r/^[a-z0-9_\-\.!~\*'\(\)]+$/)
    |> validate_exclusion(:username, @forbidden_usernames)
    |> validate_confirmation(:password, message: gettext("Passwords must match"))
    |> validate_length(:password, min: 6, too_short: gettext("Password must be at least 6 characters"))
  end

  @doc """
  Create a changeset for the user schema by passing `params`.
  If valid, generate a hashed password and insert user to Brando.repo.
  If not valid, return errors from changeset
  """
  def create(params) do
    cs = changeset(%__MODULE__{}, :create, params)

    if get_change(cs, :password) do
      put_change(cs, :password, gen_password(cs.changes[:password]))
    else
      cs
    end
  end

  @doc """
  Create an `update` changeset for the user schema by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update user in Brando.repo.
  If not valid, return errors from changeset
  """
  def update(user, params) do
    cs = changeset(user, :update, params)

    if get_change(cs, :password) do
      put_change(cs, :password, gen_password(cs.changes[:password]))
    else
      cs
    end
  end

  @doc """
  Orders by ID
  """
  def order_by_id(query) do
    from m in query, order_by: m.id
  end

  @doc """
  Checks `password` against `user`. Return bool.
  """
  def auth?(nil, _password), do: false
  def auth?(user, password), do:
    Comeonin.Bcrypt.checkpw(password, user.password)

  @doc """
  Hashes `password` using Comeonin.Bcrypt
  """
  @spec gen_password(String.t) :: String.t
  def gen_password(password), do:
    Comeonin.Bcrypt.hashpwsalt(password)

  @doc """
  Checks if `user` has `role`.
  """
  @spec role?(t, atom) :: boolean
  def role?(user, role) when is_atom(role) do
    role in user.role && true || false
  end

  @doc """
  Checks if `user` has access to admin area.
  """
  @spec can_login?(t) :: boolean
  def can_login?(user) do
    {:ok, role} = Brando.Type.Role.dump(user.role)
    role > 0 && true || false
  end

  #
  # Meta

  use Brando.Meta.Schema, [
    singular: gettext("user"),
    plural: gettext("users"),
    repr: &("#{&1.full_name} (#{&1.username})"),
    fields: [
      id: gettext("ID"),
      username: gettext("Username"),
      email: gettext("Email"),
      full_name: gettext("Full name"),
      password: gettext("Password"),
      role: gettext("Roles"),
      language: gettext("Language"),
      last_login: gettext("Last login"),
      inserted_at: gettext("Inserted at"),
      updated_at: gettext("Updated at"),
      avatar: gettext("Avatar")],
    fieldsets: [
      rights: gettext("Rights"),
      user_information: gettext("User information")
    ],
    hidden_fields: [:password, :creator]
  ]
end
