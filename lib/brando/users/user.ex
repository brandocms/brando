defmodule Brando.Users.User do
  @moduledoc """
  Ecto schema for the User schema, as well as image field definitions
  and helper functions for dealing with the user schema.
  """

  @type t :: %__MODULE__{}
  @type user :: Brando.Users.User.t() | :system

  @avatar_cfg [
    formats: [:jpg],
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

  use Gettext, backend: Brando.Gettext

  trait Brando.Trait.Password
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait Brando.Trait.ProtectRole
  trait Brando.Trait.ProtectPassword
  trait Brando.Trait.WatchLanguage

  identifier false
  persist_identifier false

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
      constraints: [min_length: 6, confirmation: true],
      required: true
  end

  assets do
    asset :avatar, :image, cfg: @avatar_cfg
  end

  relations do
    relation :config, :embeds_one, module: Brando.Users.UserConfig
  end

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
  end

  listings do
    listing do
      query %{order: [{:asc, :name}]}
      component &__MODULE__.listing_row/1
      filter label: t("Name"), filter: "name"
      filter label: t("Email"), filter: "email"
      action label: t("Edit user"), event: "edit_entry"
      action label: t("Disable user"), event: "disable_user", confirm: t("Are you sure?")
      default_actions false
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.cover image={@entry.avatar} columns={1} size={:smallest} />
    <.update_link entry={@entry} columns={14}>
      <%= @entry.name %>
      <:outside>
        <br />
        <small><%= @entry.email %></small>
        <br />
        <small class="badge"><%= @entry.role %></small>
      </:outside>
    </.update_link>
    """
  end

  forms do
    form :password do
      after_save &__MODULE__.update_password_config/2

      tab t("Content") do
        alert :info,
              t(
                "The administrator has set a mandatory password change on first login for this website."
              )

        fieldset do
          size :half
          input :password, :password, label: t("Password"), confirmation: true
        end
      end
    end

    form :default do
      after_save &__MODULE__.maybe_update_current_user/2

      tab t("Content") do
        fieldset do
          size :half
          input :name, :text, label: t("Name")
          input :email, :email, label: t("Email")
          input :password, :password, label: t("Password")
          input :language, :radios, options: :admin_languages, label: t("Language")

          input :role, :radios,
            options: [
              %{label: t("Superuser"), value: :superuser},
              %{label: t("Admin"), value: :admin},
              %{label: t("Editor"), value: :editor},
              %{label: t("User"), value: :user}
            ]
        end

        fieldset do
          size :half
          input :avatar, :image, label: t("Avatar")

          inputs_for :config do
            label t("Config")

            input :reset_password_on_first_login, :toggle,
              label: t("Reset password on first login", Brando.Users.UserConfig)

            input :show_mutation_notifications, :toggle,
              label: t("Show mutation notifications", Brando.Users.UserConfig)

            input :prefers_reduced_motion, :toggle,
              label: t("Prefers reduced motion", Brando.Users.UserConfig)
          end
        end
      end
    end
  end

  factory %{
    name: "James Williamson",
    email: "james@thestooges.com",
    password: Bcrypt.hash_pwd_salt("admin"),
    avatar: nil,
    role: :superuser,
    language: "en",
    config: %{prefers_reduced_motion: true, content_language: "en"}
  }

  def maybe_update_current_user(entry, current_user) do
    if entry.id == current_user.id do
      Phoenix.PubSub.broadcast(Brando.pubsub(), "user:#{entry.id}", {:user_update, entry})

      send(
        self(),
        {:toast,
         gettext("Current user updated. You should reload your application to see the changes.")}
      )
    end
  end

  def update_password_config(entry, _current_user) do
    Brando.Users.update_user(
      entry.id,
      %{config: %{reset_password_on_first_login: false}},
      entry
    )
  end
end
