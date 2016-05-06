defmodule Brando.UserProfileForm do
  @moduledoc """
  A form for the current user's profile. See the `Brando.Form`
  module for more documentation
  """
  use Brando.Form
  alias Brando.User
  import Brando.Gettext

  @doc false
  def get_language_choices do
    Brando.config(:admin_languages)
  end

  form "user", [schema: User, helper: :admin_user_path, class: "grid-form"] do
    fieldset gettext("User information") do
      field :full_name, :text
      field :username, :text
    end

    field :email, :email
    field :password, :password

    fieldset do
      field :language, :select,
        [default: "nb",
         choices: &__MODULE__.get_language_choices/0]
    end

    field :avatar, :file, [required: false]
    submit :save, [class: "btn btn-success"]
  end
end
