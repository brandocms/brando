defmodule Brando.Users.User do
  @moduledoc """
  Ecto schema for the User schema, as well as image field definitions
  and helper functions for dealing with the user schema.
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Users",
    schema: "User",
    singular: "user",
    plural: "users",
    gettext_module: Brando.Gettext

  content_icon "user"

  @schema_prefix "public"

  use Gettext, backend: Brando.Gettext
  import Brando.Blueprint.Listings.Components.Core
  import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]

  alias Brando.RuntimeConfig
  alias Brando.Users.UserConfig

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

  trait :password
  trait :soft_delete
  trait :timestamped
  trait :protect_role
  trait :protect_password
  trait :watch_language

  identifier false
  persist_identifier false

  attributes do
    attribute :name, :string, required: true

    attribute :email, :string,
      constraints: [format: ~r/@/],
      unique: true,
      required: true

    attribute :role, :enum, values: [:user, :editor, :admin, :superuser], required: true, default: :user
    attribute :active, :boolean, default: true
    attribute :last_login, :naive_datetime

    # Written by the presence layer when a user's last admin session goes away,
    # which is the only writer that can honestly claim to know it. `last_login`
    # stays what its name says: set once, at sign-in. See brando_165.
    attribute :last_seen, :naive_datetime
    attribute :language, :language, languages: RuntimeConfig.get(:admin_languages)

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
      query %{order: "desc active, asc name"}
      component &__MODULE__.listing_row/1
      filter label: t("Name"), key: "name"
      filter label: t("Email"), key: "email"
      action label: t("Edit user"), event: "edit_entry"
      action label: t("Disable user"), event: "disable_user", confirm: t("Are you sure?")
      action label: t("Delete user"), event: "delete_user"
      default_actions false
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.cover :if={@entry.avatar} image={@entry.avatar} columns={1} size={:thumb} class="user-avatar" />
    <div :if={!@entry.avatar} class="user-avatar user-initials" aria-hidden="true">
      <span>{String.first(@entry.name)}</span>
    </div>
    <div class="user-account">
      <.update_link entry={@entry} columns={4} class="user-identity">{@entry.name}</.update_link>
      <span class="user-email">{@entry.email}</span>
    </div>
    <.field columns={2} class="user-role">
      <span class="user-detail-label">{if Brando.Authorization.enabled?(), do: t("Legacy role"), else: t("Role")}</span>
      <span class="workspace-badge">{role_label(@entry.role)}</span>
    </.field>
    <div class="user-activity user-last-seen">
      <span class="user-detail-label">{t("Last seen")}</span>
      <.activity_time value={@entry.last_seen} />
    </div>
    <div class="user-activity user-last-login">
      <span class="user-detail-label">{t("Last logged in")}</span>
      <.activity_time value={@entry.last_login} />
    </div>
    <.field columns={2} class="user-state">
      <span class={["workspace-badge", @entry.active && @entry.last_login && "positive"]}>
        {cond do
          !@entry.active -> t("Inactive")
          is_nil(@entry.last_login) -> gettext("Never logged in")
          true -> t("Active")
        end}
      </span>
    </.field>
    """
  end

  @doc "The role's name in the admin's language."
  def role_label(:superuser), do: pgettext("role", "Superuser")
  def role_label(:admin), do: pgettext("role", "Administrator")
  def role_label(:editor), do: pgettext("role", "Editor")
  def role_label(:user), do: pgettext("role", "User")
  def role_label(role), do: to_string(role)

  defp activity_time(assigns) do
    ~H"""
    <time
      :if={@value}
      datetime={NaiveDateTime.to_iso8601(@value) <> "Z"}
      title={Brando.Utils.Datetime.format_datetime(@value, "%d %b %Y %H:%M %Z")}
    >
      {Brando.Utils.Datetime.format_datetime(@value, "%d %b %Y")}
      <small>{Brando.Utils.Datetime.format_datetime(@value, "%H:%M %Z")}</small>
    </time>
    <span :if={!@value} class="user-no-activity">{t("Not recorded")}</span>
    """
  end

  forms do
    form :default do
      after_save &__MODULE__.maybe_update_current_user/2

      tab t("Content") do
        fieldset do
          size :half
          input :name, :text, label: t("Name")
          input :email, :email, label: t("Email")
          # A saved user's password is changed with the current one, or reset by email
          input :password, :password, label: t("Password"), hidden: &__MODULE__.persisted?/1
          input :language, :radios, options: :admin_languages, label: t("Language")

          input :role, :radios,
            hidden: fn _ -> Brando.Authorization.enabled?() end,
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
            input :reset_password_on_first_login, :toggle, label: t("Reset password on first login", UserConfig)
            input :show_mutation_notifications, :toggle, label: t("Show mutation notifications", UserConfig)
            input :prefers_reduced_motion, :toggle, label: t("Prefers reduced motion", UserConfig)
          end
        end

        fieldset do
          size :half
          component &__MODULE__.password_access/1
        end
      end
    end
  end

  factory %{
    name: "James Williamson",
    email: "james@thestooges.com",
    password: "admin123",
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
        {:toast, gettext("Current user updated. You should reload your application to see the changes.")}
      )
    end
  end

  @doc false
  def persisted?(form), do: not is_nil(form.data.id)

  @doc """
  The password row of a saved user's form: your own account links to the
  page that changes it, and an administrator allowed to may email another
  user a link to choose a new one.
  """
  def password_access(%{form: form, current_user: current_user} = assigns) do
    assigns =
      assign(assigns,
        user: form.data,
        own?: form.data.id == current_user.id,
        can_reset?: persisted?(form) and Brando.Trait.ProtectPassword.allowed?(current_user, form.data)
      )

    ~H"""
    <div :if={persisted?(@form)} class="user-password-access">
      <div class="user-password-access-text">
        <span class="user-password-access-label">{gettext("Password")}</span>
        <p :if={@own?}>{gettext("Changing your password asks for the current one, and logs out your other sessions.")}</p>
        <p :if={!@own? and @can_reset?}>
          {gettext("Email %{email} a link to choose a new password. The link works once, for an hour.",
            email: @user.email
          )}
        </p>
        <p :if={!@own? and !@can_reset?}>{gettext("Only a superuser can reset the password of another user.")}</p>
      </div>
      <.link :if={@own?} navigate="/admin/users/password" class="workspace-button" data-testid="change-password">
        <Brando.HTML.icon name="key-round" />{gettext("Change password")}
      </.link>
      <button
        :if={!@own? and @can_reset?}
        type="button"
        class="workspace-button"
        phx-click="send_password_reset"
        data-testid="send-password-reset"
        data-confirm-title={gettext("Send a password reset link?")}
        data-confirm={
          gettext("%{email} gets an email with a link to choose a new password. The current password works until then.",
            email: @user.email
          )
        }
        data-confirm-ok={gettext("Send link")}
      >
        <Brando.HTML.icon name="mail" />{gettext("Send reset link")}
      </button>
    </div>
    """
  end
end
