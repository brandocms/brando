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
    plural: "users",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  trait Brando.Trait.Password
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped

  attributes do
    attribute :name, :string, required: true

    attribute :email, :string,
      constraints: [format: ~r/@/],
      unique: true,
      required: true

    attribute :role, :enum, values: [:user, :editor, :admin, :superuser], required: true
    attribute :active, :boolean, default: true
    attribute :last_login, :naive_datetime
    attribute :language, :language, languages: Brando.config(:admin_languages)

    attribute :password, :string,
      constraints: [min_length: 6],
      required: true
  end

  assets do
    asset :avatar, :image, cfg: @avatar_cfg
  end

  relations do
    relation :config, :embeds_one, module: Brando.Users.UserConfig
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

      translate :password do
        label t("Password")
        placeholder t("Password")
      end

      translate :language do
        label t("Language")
        placeholder t("Language")
      end

      translate :role do
        label t("Role")
      end

      translate :avatar do
        label t("Profile picture")
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

  listings do
    listing do
      # listing_query %{filter: %{active: false}}
      listing_field :avatar, :image, columns: 2

      listing_filters([
        [label: gettext("Name"), filter: "name"],
        [label: gettext("Email"), filter: "email"]
      ])

      listing_template """
                       <a
                        class="entry-link"
                        data-phx-link="redirect"
                        data-phx-link-state="push"
                        href="/admin/users/update/{{ entry.id }}">
                        {{ entry.name }}
                       </a><br>
                       <small>{{ entry.email }}</small><br>
                       <div class="badge">{{ entry.role }}</div>
                       """,
                       columns: 7
    end
  end

  form do
    fieldset size: :half do
      input :name, :text
      input :email, :email
      input :password, :password
      input :language, :radios, options: :languages

      input :role, :radios,
        options: [
          %{label: gettext("Superuser"), value: :superuser},
          %{label: gettext("Admin"), value: :admin},
          %{label: gettext("Editor"), value: :editor},
          %{label: gettext("User"), value: :user}
        ]
    end

    fieldset size: :half do
      input :avatar, :image

      inputs_for :config do
        input :reset_password_on_first_login, :toggle
        input :show_mutation_notifications, :toggle
      end
    end
  end
end
