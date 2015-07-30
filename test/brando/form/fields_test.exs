defmodule Brando.Form.FieldsTest do
  use ExUnit.Case, async: true
  require Brando.Form.Fields, as: F

  @opts [context: Brando.Form.Fields]

  defmodule UserForm do
    use Brando.Form

    def get_role_choices(_) do
      [[value: "1", text: "Staff"],
       [value: "2", text: "Admin"],
       [value: "4", text: "Superuser"]]
    end

    def get_status_choices(_) do
      [[value: "1", text: "Valg 1"],
       [value: "2", text: "Valg 2"]]
    end

    def selected_fun_true(_form_value, _model_value) do
      true
    end

    def selected_fun_false(_form_value, _model_value) do
      false
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
        [choices: &__MODULE__.get_role_choices/1,
         multiple: true,
         label: "Role",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :status2, :select,
        [choices: &__MODULE__.get_status_choices/1,
         default: "1",
         label: "Status",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :role2, :radio,
        [choices: &__MODULE__.get_role_choices/1,
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

  test "render_options/4" do
    assert F.render_options(:create, %{choices: &UserForm.get_status_choices/1, language: "en"},
                          "val", nil) == ["<option value=\"1\">Valg 1</option>",
                                          "<option value=\"2\">Valg 2</option>"]
  end

  test "get_required/1" do
    assert F.get_required(nil) == ""
    assert F.get_required(false) == ""
    assert F.get_required(true) == " required"
  end

  test "get_has_error/1" do
    assert F.get_has_error([]) == ""
    assert F.get_has_error(["1", "2"]) == " has-error"
  end

  test "get_choices/1" do
    opts = %{language: "en", choices: &UserForm.get_status_choices/1}
    assert F.get_choices(opts) == [[value: "1", text: "Valg 1"], [value: "2", text: "Valg 2"]]
  end

  test "concat_fields/2" do
    label = "<label>Label</label>"
    wrapped_field = "<div><input /></div>"
    assert F.concat_fields(wrapped_field, label) == label <> wrapped_field
  end

  test "div_tag/2" do
    assert F.div_tag("contents", "class") == "<div class=\"class\">contents</div>"
    assert F.div_tag("<b>contents</b>", "class class2") == "<div class=\"class class2\"><b>contents</b></div>"
  end

  test "form_group/4" do
    assert F.form_group("1234", "name", [], []) == "<div class=\"form-group\">1234</div>"
    opts = %{required: true}
    fg = F.form_group("1234", "name", opts, ["can't be blank"])
    assert fg =~ "required"
    assert fg =~ "has-error"
    assert fg =~ "fa-exclamation-circle"

    fg = F.form_group("1234", "name", opts, [])
    assert fg =~ "required"
    refute fg =~ "has-error"

    fg = F.form_group("1234", "name", [], [])
    refute fg =~ "required"
    refute fg =~ "has-error"

    opts = %{required: false}
    fg = F.form_group("1234", "name", opts, [])
    refute fg =~ "required"
    refute fg =~ "has-error"

    fg = assert F.form_group("1234", "name", opts, ["must be unique"])
    assert fg =~ "has-error"
    assert fg =~ "fa-exclamation-circle"
  end

  test "tag/4" do
    assert F.tag("select", "name", "test", "class") == "<select name=\"name\" class=\"class\">test</select>"
  end

  test "wrap/2" do
    assert F.wrap("test", nil) == "test"
    assert F.wrap("test", "wrapper_class") == "<div class=\"wrapper_class\">test</div>"
  end

  test "textarea/5" do
    assert F.textarea(:create, "name", [], nil, %{}) == ~s(<textarea name="name"></textarea>)
    assert F.textarea(:update, "name", "blah", nil, %{}) == ~s(<textarea name="name">blah</textarea>)
    assert F.textarea(:update, "name", "blah", nil, %{default: "default"}) == ~s(<textarea name="name">blah</textarea>)
    assert F.textarea(:update, "name", [], nil, %{default: "default"}) == ~s(<textarea name="name"></textarea>)
    assert F.textarea(:create, "name", [], nil, %{default: "default"}) == ~s(<textarea name="name">default</textarea>)
    assert F.textarea(:update, "name", [], nil, %{default: "default", class: "class"}) == ~s(<textarea name="name" class="class"></textarea>)
  end

  test "file/4" do
    assert F.file(:update, "user[avatar]", %{sizes: %{"thumb" => "images/default/thumb/0.jpeg"}},
                  [], %{type: :file, label: "Bilde"}) == "<div class=\"image-preview\"><img src=\"/media/images/default/thumb/0.jpeg\" /></div><input name=\"user[avatar]\" type=\"file\" />"
  end

  test "get_form_group_class/1" do
    assert F.get_form_group_class(nil) == ""
    assert F.get_form_group_class("test") == " test"
  end

  test "get_slug_from/2" do
    assert F.get_slug_from("testform[title]", []) == ""
    assert F.get_slug_from("testform[title]", %{slug_from: :name}) ==
      ~s( data-slug-from="testform[name]")
  end

  test "get_val/2" do
    assert F.get_val([]) == ""
    assert F.get_val(nil) == ""
    assert F.get_val("test") == " value=\"test\""
    assert F.get_val("test", nil) == " value=\"test\""
    assert F.get_val("test", "default") == " value=\"test\""
    assert F.get_val([], "default") == " value=\"default\""
  end

  test "input checkbox" do
    assert F.input(:checkbox, :create, "name", [], [], []) ==
      "<input name=\"name\" type=\"hidden\" value=\"false\"><input name=\"name\" value=\"true\" type=\"checkbox\" />"
    assert F.input(:checkbox, :create, "name", false, [], []) ==
      "<input name=\"name\" type=\"hidden\" value=\"false\"><input name=\"name\" value=\"true\" type=\"checkbox\" />"
    assert F.input(:checkbox, :create, "name", nil, [], []) ==
      "<input name=\"name\" type=\"hidden\" value=\"false\"><input name=\"name\" value=\"true\" type=\"checkbox\" />"
    assert F.input(:checkbox, :create, "name", true, [], []) ==
      "<input name=\"name\" type=\"hidden\" value=\"false\"><input name=\"name\" value=\"true\" type=\"checkbox\" checked=\"checked\" />"
    assert F.input(:checkbox, :create, "name", "on", [], []) ==
      "<input name=\"name\" type=\"hidden\" value=\"false\"><input name=\"name\" value=\"true\" type=\"checkbox\" checked=\"checked\" />"
  end

  test "render_errors/1" do
    assert F.render_errors([]) == ""
    assert F.render_errors(["can't be blank", "must be unique"]) =~ "Feltet er påkrevet."
    assert F.render_errors(["can't be blank", "must be unique"]) =~ "Feltet må være unikt. Verdien finnes allerede i databasen."
  end

  test "parse_error/1" do
    assert F.parse_error("can't be blank") == "Feltet er påkrevet."
    assert F.parse_error("must be unique") == "Feltet må være unikt. Verdien finnes allerede i databasen."
    assert F.parse_error("has invalid format") == "Feltet har feil format."
    assert F.parse_error("is reserved") == "Verdien er reservert."
    assert F.parse_error({"should be at least %{count} characters", count: 10}) == "Feltets verdi er for kort. Må være > 10 tegn."
  end

  test "render_help_text/1" do
    opts = %{help_text: "Help text"}
    assert F.render_help_text(nil) == ""
    assert F.render_help_text(opts) ==
      "<div class=\"help\"><i class=\"fa fa-fw fa-question-circle\"> </i><span>Help text</span></div>"
  end

  test "label/3" do
    assert F.label("name", "class", "text") ==
      ~s(<label for="name" class="class">text</label>)
  end

  test "select/6" do
    assert F.select(:create, "name", "choices", %{}, [], []) ==
      "<select name=\"name\" class=\"\">choices</select>"
    assert F.select(:create, "name", "choices", %{multiple: true}, [], []) ==
      "<select name=\"name[]\" multiple>choices</select>"
  end

  test "option/6" do
    assert F.option(:create, "choice_val", "choice_text", [], nil, nil) ==
      "<option value=\"choice_val\">choice_text</option>"
    assert F.option(:create, "choice_val", "choice_text", [], "choice_val", nil) ==
      "<option value=\"choice_val\" selected>choice_text</option>"
    assert F.option(:create, "choice_val", "choice_text", "choice_wrong", "choice_val", nil) ==
      "<option value=\"choice_val\">choice_text</option>"
    assert F.option(:create, "choice_val", "choice_text", "choice_val", "choice_val", nil) ==
      "<option value=\"choice_val\" selected>choice_text</option>"
    assert F.option(:update, "choice_val", "choice_text", "choice_val", "choice_val", &__MODULE__.UserForm.selected_fun_true/2) ==
      "<option value=\"choice_val\" selected>choice_text</option>"
    assert F.option(:update, "choice_val", "choice_text", "choice_val", "choice_val", &__MODULE__.UserForm.selected_fun_false/2) ==
      "<option value=\"choice_val\">choice_text</option>"
  end

  test "radio/7" do
    assert F.radio(:create, "choice_name", "choice_val", "choice_text", [], nil, nil) ==
      "<div class=\"radio\"><label for=\"choice_name\"></label><label for=\"choice_name\"><input name=\"choice_name\" type=\"radio\" value=\"choice_val\" />choice_text</label></div>"
    assert F.radio(:create, "choice_name", "choice_val", "choice_text", [], "choice_val", nil) ==
      "<div class=\"radio\"><label for=\"choice_name\"></label><label for=\"choice_name\"><input name=\"choice_name\" type=\"radio\" value=\"choice_val\" checked />choice_text</label></div>"
    assert F.radio(:create, "choice_name", "choice_val", "choice_text", "choice_wrong", "choice_val", nil) ==
      "<div class=\"radio\"><label for=\"choice_name\"></label><label for=\"choice_name\"><input name=\"choice_name\" type=\"radio\" value=\"choice_val\" />choice_text</label></div>"
    assert F.radio(:create, "choice_name", "choice_val", "choice_text", "choice_val", "choice_val", nil) ==
      "<div class=\"radio\"><label for=\"choice_name\"></label><label for=\"choice_name\"><input name=\"choice_name\" type=\"radio\" value=\"choice_val\" checked />choice_text</label></div>"

    assert F.radio(:create, "choice_name", "choice_val", "choice_text", "choice_val", "choice_val", &__MODULE__.UserForm.selected_fun_true/2) ==
      "<div class=\"radio\"><label for=\"choice_name\"></label><label for=\"choice_name\"><input name=\"choice_name\" type=\"radio\" value=\"choice_val\" checked />choice_text</label></div>"
    assert F.radio(:create, "choice_name", "choice_val", "choice_text", "choice_val", "choice_val", &__MODULE__.UserForm.selected_fun_false/2) ==
      "<div class=\"radio\"><label for=\"choice_name\"></label><label for=\"choice_name\"><input name=\"choice_name\" type=\"radio\" value=\"choice_val\" />choice_text</label></div>"
  end
end
