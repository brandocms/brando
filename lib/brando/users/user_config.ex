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

  import Brando.Gettext

  @primary_key false
  data_layer :embedded

  attributes do
    attribute :content_language, :string, default: Brando.config(:default_language)
    attribute :reset_password_on_first_login, :boolean, default: true
    attribute :show_mutation_notifications, :boolean, default: true
    attribute :show_onboarding, :boolean, default: false
    attribute :prefers_reduced_motion, :boolean, default: false
  end

  translations do
    context :naming do
      translate :singular, t("user config")
      translate :plural, t("user configs")
    end
  end
end
