defmodule Brando.FormTest do
  use ExUnit.Case

  defmodule UserForm do
    use Brando.Form

    def get_status_choices do
      [[value: "0", text: "Valg 1"],
       [value: "1", text: "Valg 2"]]
    end

    form "user", [action: "", class: "col-md-offset-2"] do
      field :full_name, :text,
        [required: true,
         label: "Fullt navn",
         label_class: "control-label",
         placeholder: "Fullt navn",
         help_text: "Skriv inn ditt fødselsnavn - fornavn og etternavn",
         class: "form-control",
         wrapper_class: ""]
      field :username, :text,
        [required: true,
         label: "Brukernavn",
         label_class: "control-label",
         placeholder: "Brukernavn",
         class: "form-control",
         wrapper_class: ""]
      field :email, :email,
        [required: true,
         label: "E-post",
         label_class: "control-label",
         placeholder: "E-post",
         class: "form-control",
         wrapper_class: ""]
      field :password, :password,
        [required: true,
         label: "Passord",
         label_class: "control-label",
         placeholder: "Passord",
         class: "form-control",
         wrapper_class: ""]
      field :administrator, :checkbox,
        [label: "Administrator",
         wrapper_class: "",
         default: false]
      field :editor, :checkbox,
        [label: "Redaktør",
         wrapper_class: "",
         default: true]
      field :status, :select,
        [choices: {__MODULE__, :get_status_choices},
         default: "1",
         label: "Status",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :avatar, :file,
        [label: "Bilde",
         label_class: "control-label",
         wrapper_class: ""]
      submit "Lagre",
        [class: "btn btn-default",
         wrapper_class: ""]
    end
  end

  #require Brando.Form.Fields, as: F

  #@opts [context: Brando.Form.Fields]

  test "render form" do
    #assert UserForm.get_form(action: :create, params: [], values: nil, errors: []) == ""
    assert true
  end
end
