defmodule Brando.UserForm do
  @moduledoc """
  A form for the User model. See the `Brando.Form` module for more
  documentation
  """
  use Bitwise, only_operators: true
  use Brando.Form

  @roles %{staff: 1, admin: 2, superuser: 4}

  @doc false
  def get_role_choices do
    [[value: "1", text: "Staff"],
     [value: "2", text: "Admin"],
     [value: "4", text: "Superuser"]]
  end

  @doc false
  def role_selected?(choice_value, values) do
    # first make an int out of the values list
    role_int = Enum.reduce(values, 0, fn (role, acc) ->
      cond do
        is_atom(role) -> acc + @roles[role]
        is_binary(role) -> acc + String.to_integer(role)
        is_integer(role) -> acc
      end
    end)
    # choice_value to int
    choice_int = String.to_integer(choice_value)
    (role_int &&& choice_int) == choice_int
  end

  form "user", [helper: :admin_user_path, class: "grid-form"] do
    fieldset [legend: "Brukerinfo", row_span: 2] do
      field :full_name, :text,
        [required: true,
         label: "Fullt navn",
         placeholder: "Fullt navn",
         help_text: "Skriv inn ditt fødselsnavn - fornavn og etternavn"]
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
       label: "Passord",
       placeholder: "Passord"]

    field :role, :checkbox,
      [choices: &__MODULE__.get_role_choices/0,
       is_selected: &__MODULE__.role_selected?/2,
       label: "Rolle", multiple: true]
    field :avatar, :file,
      [label: "Bilde"]
    submit "Lagre",
      [class: "btn btn-success"]

  end
end