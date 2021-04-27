defmodule Brando.Users.User do
  @moduledoc """
  Ecto schema for the User schema, as well as image field definitions
  and helper functions for dealing with the user schema.
  """

  @type t :: %__MODULE__{}
  @type user :: Brando.Users.User.t() | :system

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

  use Brando.Blueprint,
    application: "Brando",
    domain: "Users",
    schema: "User",
    singular: "user",
    plural: "users"

  import Brando.Gettext

  trait Brando.Trait.Password
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  attributes do
    attribute :name, :string, required: true

    attribute :email, :string,
      constraints: [format: ~r/@/],
      unique: true,
      required: true

    attribute :avatar, :image, @avatar_cfg
    attribute :role, Brando.Type.Role
    attribute :config, Brando.Type.UserConfig, default: %Brando.Type.UserConfig{}
    attribute :active, :boolean, default: true
    attribute :last_login, :naive_datetime

    attribute :password, :string,
      constraints: [min_length: 6],
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

  translations do
    context :naming do
      translate :singular, t("user")
      translate :plural, t("users")
    end

    context :fields do
      translate :name do
        label t("Name")
        placeholder t("Name")
      end

      translate :email do
        label t("Email")
        placeholder t("Email")
      end
    end

    context :strings do
      translate [:user, :error], t("Error")
      translate [:user, :superuser_cannot_be_deactivated], t("Superuser cannot be deactivated")
      translate [:user, :title], t("Users")
      translate [:user, :subtitle], t("Administrate users")
      translate [:user, :new], t("Create user")
      translate [:user, :edit], t("Edit user")
      translate [:user, :activate], t("Activate user")
      translate [:user, :activated], t("User activated")
      translate [:user, :deactivate], t("Deactivate user")
      translate [:user, :deactivated], t("User deactivated")
    end
  end
end
