defmodule Brando.Users.User do
  @moduledoc """
  Ecto schema for the User schema, as well as image field definitions
  and helper functions for dealing with the user schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Field.Image.Schema
  use Brando.SoftDelete.Schema

  import Brando.Gettext

  @required_fields ~w(full_name email password language)a
  @optional_fields ~w(role avatar active deleted_at)a

  @derived_fields ~w(id full_name email password language role avatar active inserted_at updated_at deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  schema "users_users" do
    field :email, :string
    field :full_name, :string
    field :password, :string
    field :avatar, Brando.Type.Image
    field :role, Brando.Type.Role
    field :active, :boolean
    field :language, :string
    field :last_login, :naive_datetime
    timestamps()
    soft_delete()
  end

  has_image_field(:avatar, %{
    allowed_mimetypes: [
      "image/jpeg",
      "image/png",
      "image/gif"
    ],
    default_size: :medium,
    upload_path: Path.join("images", "avatars"),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{
        "size" => "25",
        "quality" => 10,
        "crop" => false
      },
      "thumb" => %{
        "size" => "150x150",
        "quality" => 65,
        "crop" => true
      },
      "small" => %{
        "size" => "300x300",
        "quality" => 65,
        "crop" => true
      },
      "medium" => %{
        "size" => "500x500",
        "quality" => 65,
        "crop" => true
      },
      "large" => %{
        "size" => "700x700",
        "quality" => 65,
        "crop" => true
      },
      "xlarge" => %{
        "size" => "900x900",
        "quality" => 65,
        "crop" => true
      }
    },
    srcset: %{
      "small" => "300w",
      "medium" => "500w",
      "large" => "700w"
    }
  })

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, :create | :update, %{binary => term} | %{atom => term}) :: Ecto.Changeset.t()
  def changeset(schema, action, params \\ %{})

  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> validate_length(:password,
      min: 6,
      too_short: gettext("Password must be at least 6 characters")
    )
    |> validate_upload({:image, :avatar})
  end

  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> validate_length(:password,
      min: 6,
      too_short: gettext("Password must be at least 6 characters")
    )
    |> validate_upload({:image, :avatar})
  end
end
