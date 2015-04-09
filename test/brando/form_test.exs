defmodule Brando.FormTest do
  use ExUnit.Case, async: true
  import Brando.Form

  defmodule TestForm do
    use Brando.Form

    form "test", [helper: :admin_user_path, class: "grid-form"] do
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

    def get_role_choices do
      [[value: "1", text: "Staff"],
       [value: "2", text: "Admin"],
       [value: "4", text: "Superuser"]]
    end

    def get_status_choices do
      [[value: "1", text: "Valg 1"],
       [value: "2", text: "Valg 2"]]
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
      field :role, :select,
        [choices: &__MODULE__.get_role_choices/0,
         multiple: true,
         label: "Role",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :status2, :select,
        [choices: &__MODULE__.get_status_choices/0,
         default: "1",
         label: "Status",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :role2, :radio,
        [choices: &__MODULE__.get_role_choices/0,
        label: "Rolle 2"]
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
       status2: [type: :select, multiple: true, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
       status3: [type: :radio, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
       status4: [type: :checkbox, multiple: true, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
       email: [type: :email, required: true, label: "E-mail", placeholder: "E-mail"],
       username: [type: :text, required: true, label: "Username", placeholder: "Username"]
     ]
    errors = [username: "has invalid format", email: "has invalid format", password: "can't be blank", email: "can't be blank", full_name: "can't be blank", username: "can't be blank"]
    f = UserForm.render_fields("user", form_fields, :create, [], nil, errors)
    assert f ==
      ["<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group required has-error\">\n  <label for=\"user[username]\" class=\"\">Username</label><input name=\"user[username]\" type=\"text\" placeholder=\"Username\" />\n  <div class=\"error\"><i class=\"fa fa-exclamation-circle\"> </i> Feltet har feil format.</div><div class=\"error\"><i class=\"fa fa-exclamation-circle\"> </i> Feltet er påkrevet.</div>\n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group required has-error\">\n  <label for=\"user[email]\" class=\"\">E-mail</label><input name=\"user[email]\" type=\"email\" placeholder=\"E-mail\" />\n  <div class=\"error\"><i class=\"fa fa-exclamation-circle\"> </i> Feltet har feil format.</div><div class=\"error\"><i class=\"fa fa-exclamation-circle\"> </i> Feltet er påkrevet.</div>\n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status4]\" class=\"\">Status</label><div class=\"checkboxes\"><label for=\"user[status4][]\"></label><label for=\"user[status4][]\"><input name=\"user[status4][]\" type=\"checkbox\" value=\"1\" checked />Valg 1</label></div><div class=\"checkboxes\"><label for=\"user[status4][]\"></label><label for=\"user[status4][]\"><input name=\"user[status4][]\" type=\"checkbox\" value=\"2\" />Valg 2</label></div>\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status3]\" class=\"\">Status</label><div class=\"radio\"><label for=\"user[status3]\"></label><label for=\"user[status3]\"><input name=\"user[status3]\" type=\"radio\" value=\"1\" checked />Valg 1</label></div><div class=\"radio\"><label for=\"user[status3]\"></label><label for=\"user[status3]\"><input name=\"user[status3]\" type=\"radio\" value=\"2\" />Valg 2</label></div>\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status2]\" class=\"\">Status</label><select name=\"user[status2][]\" multiple><option value=\"1\" selected>Valg 1</option><option value=\"2\">Valg 2</option></select>\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status]\" class=\"\">Status</label><select name=\"user[status]\" class=\"\"><option value=\"1\" selected>Valg 1</option><option value=\"2\">Valg 2</option></select>\n  \n</div>\n</div>",
       "<fieldset><legend><br>Permissions</legend><div data-row-span=\"2\">",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[administrator]\" class=\"\"></label><label for=\"user[administrator]\" class=\"\"><input name=\"user[administrator]\" type=\"checkbox\" />Administrator</label></div>\n  \n</div>\n",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[editor]\" class=\"\"></label><label for=\"user[editor]\" class=\"\"><input name=\"user[editor]\" type=\"checkbox\" checked=\"checked\" />Editor</label></div>\n  \n</div>\n",
       "</div></fieldset>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[avatar]\" class=\"\">Avatar</label><input name=\"user[avatar]\" type=\"file\" />\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <input name=\"user[submit]\" type=\"submit\" value=\"Save\" class=\"btn btn-default\" />\n  \n</div>\n</div>"]
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
       status2: [type: :checkbox, multiple: true, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
       status3: [type: :radio, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
       email: [type: :email, required: true, label: "E-mail", placeholder: "E-mail"]]
    values = %Brando.Users.Model.User{avatar: nil,
                                      email: "test@email.com",
                                      role: 4,
                                      full_name: "Test Name", id: 1,
                                      inserted_at: %Ecto.DateTime{day: 7, hour: 4, min: 36, month: 12, sec: 26, year: 2014},
                                      last_login: %Ecto.DateTime{day: 9, hour: 5, min: 2, month: 12, sec: 36, year: 2014},
                                      password: "$2a$12$abcdefghijklmnopqrstuvwxyz",
                                      updated_at: %Ecto.DateTime{day: 14, hour: 21, min: 36, month: 1, sec: 53, year: 2015},
                                      username: "test"}
    f = UserForm.render_fields("user", form_fields, :update, [], values, nil)
    assert f ==
      ["<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group required\">\n  <label for=\"user[email]\" class=\"\">E-mail</label><input name=\"user[email]\" type=\"email\" value=\"test@email.com\" placeholder=\"E-mail\" />\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status3]\" class=\"\">Status</label><div class=\"radio\"><label for=\"user[status3]\"></label><label for=\"user[status3]\"><input name=\"user[status3]\" type=\"radio\" value=\"1\" />Valg 1</label></div><div class=\"radio\"><label for=\"user[status3]\"></label><label for=\"user[status3]\"><input name=\"user[status3]\" type=\"radio\" value=\"2\" />Valg 2</label></div>\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status2]\" class=\"\">Status</label><div class=\"checkboxes\"><label for=\"user[status2][]\"></label><label for=\"user[status2][]\"><input name=\"user[status2][]\" type=\"checkbox\" value=\"1\" />Valg 1</label></div><div class=\"checkboxes\"><label for=\"user[status2][]\"></label><label for=\"user[status2][]\"><input name=\"user[status2][]\" type=\"checkbox\" value=\"2\" />Valg 2</label></div>\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[status]\" class=\"\">Status</label><select name=\"user[status]\" class=\"\"><option value=\"1\">Valg 1</option><option value=\"2\">Valg 2</option></select>\n  \n</div>\n</div>",
       "<fieldset><div data-row-span=\"2\">",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[administrator]\" class=\"\"></label><label for=\"user[administrator]\" class=\"\"><input name=\"user[administrator]\" type=\"checkbox\" />Administrator</label></div>\n  \n</div>\n",
       "<div data-field-span=\"1\" class=\"form-group\">\n  <div class=\"checkbox\"><label for=\"user[editor]\" class=\"\"></label><label for=\"user[editor]\" class=\"\"><input name=\"user[editor]\" type=\"checkbox\" checked=\"checked\" />Editor</label></div>\n  \n</div>\n",
       "</div></fieldset>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <label for=\"user[avatar]\" class=\"\">Avatar</label><input name=\"user[avatar]\" type=\"file\" />\n  \n</div>\n</div>",
       "<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <input name=\"user[submit]\" type=\"submit\" value=\"Save\" class=\"btn btn-default\" />\n  \n</div>\n</div>"]
  end

  test "get_choices/1" do
    assert get_choices(&UserForm.get_status_choices/0) == [[value: "1", text: "Valg 1"], [value: "2", text: "Valg 2"]]
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
    assert render_options(:create, [choices: &UserForm.get_status_choices/0],
                          "val", nil) == ["<option value=\"1\">Valg 1</option>",
                                          "<option value=\"2\">Valg 2</option>"]
  end

  # test "get_form" do
  #   assert TestForm.get_form(type: :create, action: :create, params: [], values: nil, errors: nil) == {:safe,
  #           "<form class=\"grid-form\" role=\"form\" action=\"/admin/brukere\" method=\"POST\"><input name=\"_csrf_token\" type=\"hidden\" value=\"C5JmQ/F4CaqcAB2RnLjjYlpWuodx0ga8FHcdgtuaJRg=\"><fieldset><legend><br>Brukerinfo</legend><div data-row-span=\"2\">\n<div data-field-span=\"1\" class=\"form-group required\">\n  <label for=\"test[full_name]\" class=\"\">Fullt navn</label><input name=\"test[full_name]\" type=\"text\" placeholder=\"Fullt navn\" />\n  \n</div>\n\n<div data-field-span=\"1\" class=\"form-group required\">\n  <label for=\"test[username]\" class=\"\">Brukernavn</label><input name=\"test[username]\" type=\"text\" placeholder=\"Brukernavn\" />\n  \n</div>\n\n<div data-row-span=\"1\"><div data-field-span=\"1\" class=\"form-group\">\n  <input name=\"test[submit]\" type=\"submit\" value=\"Submit\" />\n  \n</div>\n</div>\n</div></fieldset></form>"}
  # end

  test "method_override/1" do
    assert method_override(:update) == "<input name=\"_method\" type=\"hidden\" value=\"patch\" />"
    assert method_override(:delete) == "<input name=\"_method\" type=\"hidden\" value=\"delete\" />"
    assert method_override(:what) == ""
  end

  test "get_method/1" do
    assert get_method(:update) == " method=\"POST\""
    assert get_method(:delete) == " method=\"POST\""
    assert get_method(:what) == " method=\"GET\""
  end

  test "field name clash" do
    assert_raise ArgumentError, "field `full_name` was already set on schema", fn ->
      defmodule FormDuplicateFields do
        use Brando.Form
        form "test", [helper: :admin_user_path, class: "grid-form"] do
          field :full_name, :text,
            [required: true]
          field :full_name, :text,
            [required: true]
          submit "Submit", [name: "submit"]
        end
      end
    end
  end

  test "submit name clash" do
    assert_raise ArgumentError, "submit field `submit` was already set on schema", fn ->
      defmodule FormDuplicateFields do
        use Brando.Form
        form "test", [helper: :admin_user_path, class: "grid-form"] do
          submit "Submit", [name: "submit"]
          submit "Submit", [name: "submit"]
        end
      end
    end
  end

  test "nonexistant field type" do
    assert_raise ArgumentError, "`:foo` is not a valid field type", fn ->
      defmodule FormDuplicateFields do
        use Brando.Form
        form "test", [helper: :admin_user_path, class: "grid-form"] do
          field :full_name, :foo
        end
      end
    end
  end
end
