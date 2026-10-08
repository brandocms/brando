defmodule Brando.Users.UserConfig do
  @moduledoc """
  Defines a schema for a user configuration field.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Users",
    schema: "UserConfig",
    singular: "user_config",
    plural: "user_configs",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  @primary_key false
  data_layer :embedded

  attributes do
    attribute :content_language, :string, default: Brando.RuntimeConfig.get(:default_language)
    attribute :reset_password_on_first_login, :boolean, default: true
    attribute :show_mutation_notifications, :boolean, default: true
    attribute :show_onboarding, :boolean, default: false
    attribute :prefers_reduced_motion, :boolean, default: false

    # Mentions and notifications routed to the user by email: one email
    # each (`:off`), or a daily or weekly summary (`Brando.Notifications.Digest`)
    attribute :notification_digest, :enum, values: [:off, :daily, :weekly], default: :off
  end

  translations do
    context :naming do
      translate :singular, t("user config")
      translate :plural, t("user configs")
    end
  end
end
