defmodule Brando.Users.User do
  @moduledoc """
  Ecto schema for the User schema, as well as image field definitions
  and helper functions for dealing with the user schema.
  """

  @type t :: %__MODULE__{}
  @type user :: Brando.Users.User.t() | :system

  @application "Brando"
  @domain "Users"
  @schema "User"
  @singular "user"
  @plural "users"

  @avatar_cfg [
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "medium",
    upload_path: Path.join("images", "avatars"),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 10, "crop" => false},
      "thumb" => %{"size" => "150x150", "quality" => 65, "crop" => true},
      "small" => %{"size" => "300x300", "quality" => 65, "crop" => true},
      "medium" => %{"size" => "500x500", "quality" => 65, "crop" => true},
      "large" => %{"size" => "700x700", "quality" => 65, "crop" => true},
      "xlarge" => %{"size" => "900x900", "quality" => 65, "crop" => true}
    },
    srcset: [
      {"small", "300w"},
      {"medium", "500w"},
      {"large", "700w"}
    ]
  ]

  use Brando.Blueprint
  import Brando.Gettext

  trait Brando.Traits.Password
  trait Brando.Traits.SoftDelete

  attributes do
    attribute :name, :string, required: true

    attribute :email, :string,
      validate: [format: ~r/@/],
      unique: true,
      required: true

    attribute :avatar, :image, @avatar_cfg
    attribute :role, Brando.Type.Role
    attribute :config, Brando.Type.UserConfig, default: %Brando.Type.UserConfig{}
    attribute :language, :string, required: true
    attribute :active, :boolean, default: true
    attribute :last_login, :naive_datetime

    attribute :password, :string,
      validate: [min_length: 6],
      required: true
  end

  identifier "{{ entry.name }}"

  @derived_fields ~w(
    id
    name
    email
    password
    language
    role
    avatar
    active
    inserted_at
    updated_at
    deleted_at
  )a

  @derive {Jason.Encoder, only: @derived_fields}

  # meta :en, singular: "user", plural: "users"
  # meta :no, singular: "bruker", plural: "brukere"

  # absolute_url false

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """

  # def changeset(schema, params, user) do
  #   schema
  #   # |> cast(params, @required_fields ++ @optional_fields)
  #   # |> validate_required(@required_fields)
  #   # |> validate_format(:email, ~r/@/)
  #   # |> unique_constraint(:email)
  #   # |> validate_length(:password,
  #   #   min: 6,
  #   #   too_short: gettext("Password must be at least 6 characters")
  #   # )
  #   # |> maybe_update_password()

  #   # |> validate_upload({:image, :avatar}, user)
  # end
end
