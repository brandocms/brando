defmodule Brando.Users.Form.UserForm do
  @moduledoc """
  A form module for the User model. See the form module for more
  documentation
  """
  use Brando.Form

  @doc false
  def get_status_choices do
    [[value: "0", text: "Valg 1"],
     [value: "1", text: "Valg 2"]]
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

    fieldset [legend: "Rettigheter", row_span: 2] do
      field :administrator, :checkbox,
        [label: "Administrator",
         default: false]
      field :editor, :checkbox,
        [label: "Redaktør",
         default: true]
    end

    field :status, :select,
      [choices: {__MODULE__, :get_status_choices},
       default: "1",
       label: "Status"]
    field :avatar, :file,
      [label: "Bilde"]
    submit "Lagre",
      [class: "btn btn-default"]

  end
end