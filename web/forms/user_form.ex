defmodule Brando.UserForm do
  @moduledoc """
  A form for the User model. See the `Brando.Form` module for more
  documentation
  """
  use Bitwise, only_operators: true
  use Brando.Form
  alias Brando.User
  import Brando.Gettext

  @doc false
  def get_language_choices() do
    Brando.config(:admin_languages)
  end

  @doc false
  def get_role_choices() do
    [[value: "1", text: "Staff"],
     [value: "2", text: "Admin"],
     [value: "4", text: "Superuser"]]
  end

  @doc false
  def role_selected?(choice_value, values) do
    {:ok, role_int} = Brando.Type.Role.dump(values)
    choice_int = String.to_integer(choice_value)
    (role_int &&& choice_int) == choice_int
  end

  form "user", [schema: User, helper: :admin_user_path, class: "grid-form"] do
    fieldset gettext("User information") do
      field :full_name, :text
      field :username, :text
    end

    field :email, :email
    field :password, :password, [confirm: true]

    fieldset gettext("Rights") do
      field :role, :checkbox,
        [choices: &__MODULE__.get_role_choices/0,
         is_selected: &__MODULE__.role_selected?/2,
         empty_value: 0, multiple: true]
    end

    fieldset do
      field :language, :select,
        [default: "en",
         choices: &__MODULE__.get_language_choices/0]
    end

    field :avatar, :file, [required: false]
    submit :save, [class: "btn btn-success"]
  end
end
