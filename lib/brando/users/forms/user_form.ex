defmodule Brando.Users.Form.UserForm do
  @moduledoc """
  A form for the User model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  @doc false
  def get_role_choices do
    [[value: "1", text: "Staff"],
     [value: "2", text: "Admin"],
     [value: "4", text: "Superuser"]]
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
      label: "Rolle", multiple: true]
    field :avatar, :file,
      [label: "Bilde"]
    submit "Lagre",
      [class: "btn btn-default"]

  end
end