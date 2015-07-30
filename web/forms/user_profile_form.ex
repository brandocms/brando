defmodule Brando.UserProfileForm do
  @moduledoc """
  A form for the current user's profile. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  @doc false
  def get_language_choices(_) do
    Brando.config(:admin_languages)
  end

  form "user", [model: Brando.User, helper: :admin_user_path, class: "grid-form"] do
    fieldset {:i18n, "fieldset.user_info"} do
      field :full_name, :text, [required: true]
      field :username, :text,
        [required: true]
    end

    field :email, :email,
      [required: true]
    field :password, :password,
      [required: true]

    fieldset do
      field :language, :select,
        [required: true,
        default: "no",
        choices: &__MODULE__.get_language_choices/1]
    end

    field :avatar, :file
    submit :save, [class: "btn btn-success"]
  end
end