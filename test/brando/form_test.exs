defmodule Brando.TestHelpers do
  def test_path(_conn, _action, _params) do
    "/some/trash"
  end
end

defmodule Brando.FormTest do
  use ExUnit.Case
  import Brando.Form

  defmodule TestForm do
    use Brando.Form

    form "test", [helper: :test_path, class: "grid-form"] do
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
        submit "Submit", [name: "submit"]
      end
    end
  end

  defmodule UserForm do
    use Brando.Form

    def get_status_choices do
      [[value: "0", text: "Valg 1"],
       [value: "1", text: "Valg 2"]]
    end

    form "user", [helper: :admin_user_path, class: "grid-form"] do
      field :full_name, :text,
        [required: true,
         label: "Full name",
         label_class: "control-label",
         placeholder: "Full name",
         help_text: "Enter full name",
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
         label: "E-mail",
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
        [label: "Editor",
         wrapper_class: "",
         default: true]
      field :status, :select,
        [choices: &__MODULE__.get_status_choices/0,
         default: "1",
         label: "Status",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :avatar, :file,
        [label: "Avatar",
         label_class: "control-label",
         wrapper_class: ""]
      submit "Save",
        [class: "btn btn-default",
         wrapper_class: ""]
    end
  end

  test "render_fields/6 :create" do
    form_fields =
      [submit: [type: :submit, text: "Save", class: "btn btn-default"],
       avatar: [type: :file, label: "Avatar"],
       fs123477010: [type: :fieldset_close],
       editor: [type: :checkbox, in_fieldset: 2, label: "Editor", default: true],
       administrator: [type: :checkbox, in_fieldset: 2, label: "Administrator", default: false],
       fs34070328: [type: :fieldset, legend: "Permissions", row_span: 2],
       status: [type: :select, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
       email: [type: :email, required: true, label: "E-mail", placeholder: "E-mail"]]
    f = UserForm.render_fields("user", form_fields, :create, [], nil, nil)
    assert f ==
      ["<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group required\">\n  <label for=\"user[email]\" class=\"\">E-mail</label><input name=\"user[email]\" type=\"email\" placeholder=\"E-mail\" />\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status]\" class=\"\">Status</label><select name=\"user[status]\" class=\"\"><option value=\"0\">Valg 1</option><option value=\"1\" selected>Valg 2</option></select>\n  \n</div>\n</div>",
       "<fieldset><legend><br>Permissions</legend><div data-row-span=\"2\">",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[administrator]\" class=\"\"></label><label for=\"user[administrator]\" class=\"\"><input name=\"user[administrator]\" type=\"checkbox\" />Administrator</label></div>\n  \n</div>\n",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[editor]\" class=\"\"></label><label for=\"user[editor]\" class=\"\"><input name=\"user[editor]\" type=\"checkbox\" checked=\"checked\" />Editor</label></div>\n  \n</div>\n",
       "</div></fieldset>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[avatar]\" class=\"\">Avatar</label><input name=\"user[avatar]\" type=\"file\" />\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <input name=\"user[submit]\" type=\"submit\" class=\"btn btn-default\" />\n  \n</div>\n</div>"]
  end

  test "render_fields/6 :update" do
    form_fields =
      [submit: [type: :submit, text: "Save", class: "btn btn-default"],
       avatar: [type: :file, label: "Avatar"],
       fs123477010: [type: :fieldset_close],
       editor: [type: :checkbox, in_fieldset: 2, label: "Editor", default: true],
       administrator: [type: :checkbox, in_fieldset: 2, label: "Administrator", default: false],
       fs34070328: [type: :fieldset, row_span: 2],
       status: [type: :select, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
       email: [type: :email, required: true, label: "E-mail", placeholder: "E-mail"]]
    values = %Brando.Users.Model.User{administrator: true, avatar: "images/default/0.jpeg",
                                      editor: true, email: "test@email.com",
                                      full_name: "Test Name", id: 1,
                                      inserted_at: %Ecto.DateTime{day: 7, hour: 4, min: 36, month: 12, sec: 26, year: 2014},
                                      last_login: %Ecto.DateTime{day: 9, hour: 5, min: 2, month: 12, sec: 36, year: 2014},
                                      password: "$2a$12$abcdefghijklmnopqrstuvwxyz",
                                      updated_at: %Ecto.DateTime{day: 14, hour: 21, min: 36, month: 1, sec: 53, year: 2015},
                                      username: "test"}
    f = UserForm.render_fields("user", form_fields, :update, [], values, nil)
    assert f ==
      ["<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group required\">\n  <label for=\"user[email]\" class=\"\">E-mail</label><input name=\"user[email]\" type=\"email\" value=\"test@email.com\" placeholder=\"E-mail\" />\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status]\" class=\"\">Status</label><select name=\"user[status]\" class=\"\"><option value=\"0\">Valg 1</option><option value=\"1\">Valg 2</option></select>\n  \n</div>\n</div>",
       "<fieldset><div data-row-span=\"2\">",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[administrator]\" class=\"\"></label><label for=\"user[administrator]\" class=\"\"><input name=\"user[administrator]\" type=\"checkbox\" checked=\"checked\" />Administrator</label></div>\n  \n</div>\n",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[editor]\" class=\"\"></label><label for=\"user[editor]\" class=\"\"><input name=\"user[editor]\" type=\"checkbox\" checked=\"checked\" />Editor</label></div>\n  \n</div>\n",
       "</div></fieldset>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[avatar]\" class=\"\">Avatar</label><input name=\"user[avatar]\" type=\"file\" value=\"images/default/0.jpeg\" />\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <input name=\"user[submit]\" type=\"submit\" class=\"btn btn-default\" />\n  \n</div>\n</div>"]
  end

  test "get_choices/1" do
    assert get_choices(&UserForm.get_status_choices/0) == [[value: "0", text: "Valg 1"], [value: "1", text: "Valg 2"]]
  end

  test "get_value/2" do
    values = %{"a" => "a val", "b" => "b val"}
    assert get_value(values, :a) == "a val"
    assert get_value(values, :c) == []
    assert get_value([], :c) == []
  end

  test "get_errors/2" do
    errors = [a: "error a", b: "error b"]
    assert get_errors(errors, :a) == ["error a"]
    errors = [a: "error a", b: "error b", a: "another error a"]
    assert get_errors(errors, :a) == ["error a", "another error a"]
  end

  test "render_choices/4" do
    assert render_choices(:create, [choices: &UserForm.get_status_choices/0],
                          "val", nil) == ["<option value=\"0\">Valg 1</option>",
                                          "<option value=\"1\">Valg 2</option>"]
  end

  test "get_form" do
    assert TestForm.get_form(action: :create, params: [], values: nil, errors: nil) == {:safe,
      "<form class=\"grid-form\" role=\"form\" action=\"/some/trash\" method=\"POST\"><fieldset><legend><br>Brukerinfo</legend><div data-row-span=\"2\">\n<div data-field-span=\"1\" class=\"form-group required\">\n  <label for=\"test[full_name]\" class=\"\">Fullt navn</label><input name=\"test[full_name]\" type=\"text\" placeholder=\"Fullt navn\" />\n  \n</div>\n\n<div data-field-span=\"1\" class=\"form-group required\">\n  <label for=\"test[username]\" class=\"\">Brukernavn</label><input name=\"test[username]\" type=\"text\" placeholder=\"Brukernavn\" />\n  \n</div>\n\n<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <input name=\"test[submit]\" type=\"submit\" />\n  \n</div>\n</div>\n</div></fieldset></form>"}
  end

  test "method_override/1" do
    assert method_override(:update) == "<input name=\"_method\" type=\"hidden\" value=\"patch\" />"
    assert method_override(:destroy) == "<input name=\"_method\" type=\"hidden\" value=\"delete\" />"
    assert method_override(:what) == ""
  end

  test "get_method/1" do
    assert get_method(:update) == " method=\"POST\""
    assert get_method(:destroy) == " method=\"POST\""
    assert get_method(:what) == " method=\"GET\""
  end
end
