defmodule Brando.UserForm do
  @moduledoc """
  A form for the User model. See the `Brando.Form` module for more
  documentation
  """
  use Bitwise, only_operators: true
  use Brando.Form

  @roles Application.get_env(:brando, Brando.Type.Role) |> Keyword.get(:roles)

  @doc false
  def get_role_choices do
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

  form "user", [helper: :admin_user_path, class: "grid-form"] do
    fieldset "Brukerinfo" do
      field :full_name, :text,
        [required: true,
         label: "Fullt navn",
         placeholder: "Fullt navn"]
      field :username, :text,
        [required: true,
         label: "Brukernavn",
         placeholder: "Brukernavn"]
    end

    field :email, :email,
      [required: true,
       label: "E-post",
       placeholder: "E-post"]
    field :password, :password,
      [required: true,
       confirm: true,
       label: "Passord",
       placeholder: "Passord"]

    fieldset "Rettigheter" do
      field :role, :checkbox,
        [choices: &__MODULE__.get_role_choices/0,
         is_selected: &__MODULE__.role_selected?/2,
         empty_value: 0,
         label: "Rolle", multiple: true]
    end

    field :avatar, :file,
      [label: "Bilde"]
    submit "Lagre",
      [class: "btn btn-success"]
  end
end