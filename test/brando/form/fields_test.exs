defmodule Brando.Form.FieldsTest do
  use ExUnit.Case, async: true
  require Brando.Form.Fields, as: F
  import Brando.Form.Fields.Utils
  alias Brando.Form.Field

  defmodule UserForm do
    use Bitwise, only_operators: true
    use Brando.Form

    def get_role_choices() do
      [[value: "1", text: "Staff"],
       [value: "2", text: "Admin"],
       [value: "4", text: "Superuser"]]
    end

    def role_selected?(choice_value, values) do
      {:ok, role_int} = Brando.Type.Role.dump(values)
      choice_int = String.to_integer(choice_value)
      (role_int &&& choice_int) == choice_int
    end

    def get_status_choices() do
      [[value: "1", text: "Valg 1"],
       [value: "2", text: "Valg 2"]]
    end

    def get_skills_choices() do
      [[value: "1", text: "Skill 1"],
       [value: "2", text: "Skill 2"],
       [value: "3", text: "Skill 3"]]
    end

    def skills_selected?(choice_value, values) do
      choice_value in values
    end

    def selected_fun_true(_form_value, _schema_value) do
      true
    end

    def selected_fun_false(_form_value, _schema_value) do
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
        [choices: &__MODULE__.get_role_choices/0,
         multiple: true,
         label: "Role",
         language: "en",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :status2, :select,
        [choices: &__MODULE__.get_status_choices/0,
         default: "1",
         label: "Status",
         language: "en",
         label_class: "control-label",
         class: "form-control",
         wrapper_class: ""]
      field :role2, :radio,
        [choices: &__MODULE__.get_role_choices/0,
         language: "en",
         label: "Rolle 2"]
      field :skills, :checkbox,
        [choices: &__MODULE__.get_skills_choices/0,
         multiple: true,
         label: "Skills"]
      field :skills2, :checkbox,
        [label: "Skills single"]
      field :avatar, :file,
        [label: "Avatar",
         label_class: "control-label",
         wrapper_class: ""]
      submit "Save",
        [class: "btn btn-default",
         wrapper_class: ""]
    end
  end

  test "get_choices/1" do
    field = %Field{
      opts: %{language: "en", choices: &UserForm.get_status_choices/0}
    }
    assert F.get_choices(field) == [[value: "1", text: "Valg 1"],
                                   [value: "2", text: "Valg 2"]]
  end

  test "get_val/2" do
    assert F.get_val([]) == ""
    assert F.get_val(nil) == ""
    assert F.get_val("test") == "test"
    assert F.get_val("test", nil) == "test"
    assert F.get_val(["test", "ing"], nil) == "test,ing"
    assert F.get_val("test", "default") == "test"
    assert F.get_val(nil, "default") == "default"
  end

  test "render_errors/1" do
    assert F.render_errors([]) == []
    assert Enum.join(F.render_errors(["can't be blank", "must be unique"])) =~ "can&#39;t be blank"
    assert Enum.join(F.render_errors(["can't be blank", "must be unique"])) =~ "must be unique"
  end

  test "parse_error/1" do
    assert F.parse_error("can't be blank")
           == "can't be blank"
    assert F.parse_error("must be unique")
           == "must be unique"
    assert F.parse_error("has invalid format")
           == "has invalid format"
    assert F.parse_error("is reserved")
           == "is reserved"
    assert F.parse_error({"should be at least %{count} characters", count: 10})
           == "should be at least 10 characters"
  end

  test "render_help_text/1" do
    field = %Field{opts: %{test: "hello"}}
    assert F.render_help_text(field) == ""

    field = %Field{schema: Brando.FormTest.MyUser, name: :full_name, opts: %{test: "hello"}}
    assert F.render_help_text(field) ==
      "<div class=\"help\"><i class=\"fa fa-fw fa-question-circle\"> </i><span>Full name help</span></div>"

    field = %Field{}
    assert F.render_help_text(field) == ""
  end

  test "get_selected" do
    assert F.get_selected("a", "a")
    assert F.get_selected("a", ["a", "b"])
    refute F.get_selected("c", ["a", "b"])
  end

  test "get_checked" do
    assert F.get_checked("a", "a")
    assert F.get_checked("a", ["a", "b"])
    refute F.get_checked("c", ["a", "b"])
  end

  test "get_placeholder" do
    assert F.get_placeholder(%{opts: %{placeholder: "test"}}) == "test"
    assert F.get_placeholder(%{opts: %{placeholder: nil}}) == nil
    assert F.get_placeholder(%{name: :email, schema: Brando.User}) == "Email"
  end

  #
  # add_label

  test "add_label() without label data" do
    field = %Brando.Form.Field{}

    assert field == F.add_label(field)
  end

  #
  # Field rendering

  test "render_field :text" do
    field = %Brando.Form.Field{
      errors: nil,
      form_type: :update,
      name: :name,
      opts: %{
        action: :update,
        changeset: nil,
        params: "26",
        type: :update
      },
      schema: Brando.ImageSeries,
      source: "imageseries",
      type: :text,
      value: "Series name"
    }

    assert F.render_field(field).html
           == ~s(<div class="form-row"><div class="form-group required">) <>
              ~s(<label for="imageseries[name]">Name</label>) <>
              ~s(<input name="imageseries[name]" placeholder="Name" type="text" value="Series name"></div></div>)

    field =
      field
      |> Map.put(:html, [])
      |> put_in_opts(:confirm, true)

    assert F.render_field(field).html
           == ~s(<div class="form-row"><div class="form-group required">) <>
              ~s(<label for="imageseries[name]">Name</label>) <>
              ~s(<input name="imageseries[name]" placeholder="Name" type="text" value="Series name"></div>) <>
              ~s(<div class="form-group required"><label for="imageseries[name_confirmation]">) <>
              ~s(Confirm Name</label><input name="imageseries[name_confirmation]" ) <>
              ~s(placeholder="Confirm Name" type="text" value="Series name"></div></div>)
  end

  test "render_field :password" do
    field = %Brando.Form.Field{
      errors: nil,
      form_type: :update,
      name: :password,
      opts: %{
        action: :update,
        changeset: nil,
        params: "26",
        type: :update
      },
      schema: Brando.User,
      source: "user",
      type: :password,
      value: "abcdefg"
    }

    assert F.render_field(field).html
           == ~s(<div class="form-row"><div class="form-group required">) <>
              ~s(<label for="user[password]">Password</label>) <>
              ~s(<input name="user[password]" placeholder="Password" type="password" value="abcdefg"></div></div>)

    field = %Brando.Form.Field{
      errors: nil,
      form_type: :update,
      name: :password,
      opts: %{
        action: :update,
        changeset: nil,
        params: "26",
        type: :update,
        confirm: true
      },
      schema: Brando.User,
      source: "user",
      type: :password,
      value: "abcdefg"
    }

    assert F.render_field(field).html
           == ~s(<div class="form-row"><div class="form-group required">) <>
              ~s(<label for="user[password]">Password</label>) <>
              ~s(<input name="user[password]" placeholder="Password" type="password" value="abcdefg"></div>) <>
              ~s(<div class="form-group required"><label for="user[password_confirmation]">) <>
              ~s(Confirm Password</label><input name="user[password_confirmation]" ) <>
              ~s(placeholder="Confirm Password" type="password" value="abcdefg"></div></div>)
  end

  test "render_field :textarea" do
    field = %Brando.Form.Field{
      errors: nil,
      form_type: :update,
      name: :description,
      opts: %{
        action: :update,
        changeset: nil,
        params: "26",
        type: :update,
        label: "Description"
      },
      schema: Brando.User,
      source: "user",
      type: :textarea,
      value: "text"
    }

    assert F.render_field(field).html
           == ~s(<div class="form-row"><div class="form-group required no-height">) <>
              ~s(<label for="user[description]">Description</label>) <>
              ~s(<textarea name="user[description]">text</textarea></div></div>)

    field =
      field
      |> put_html(nil)
      |> put_in_field(:form_type, :create)
      |> put_in_field(:value, nil)
      |> put_in_opts(:default, "default")

    assert F.render_field(field).html
           == ~s(<div class="form-row"><div class="form-group required no-height">) <>
              ~s(<label for="user[description]">Description</label>) <>
              ~s(<textarea name="user[description]">default</textarea></div></div>)
  end

  test "render_field :radio" do
    field = %Brando.Form.Field{
      errors: nil,
      form_type: :update,
      name: :description,
      opts: %{
        choices: &UserForm.get_skills_choices/0,
        is_selected: &UserForm.skills_selected?/2,
        action: :update,
        changeset: nil,
        params: "26",
        type: :update,
        label: "Description"
      },
      schema: Brando.User,
      source: "user",
      type: :radio,
      value: ["1", "2"]
    }

    assert F.render_field(field).html
           == "<div class=\"form-row\"><div class=\"form-group required\">" <>
           "<label for=\"user[description]\">Description</label><div>" <>
           "<label for=\"user[description]\"></label><label for=\"user[description]\">" <>
           "<input checked=\"checked\" name=\"user[description]\" type=\"radio\" value=\"1\">" <>
           "Skill 1</label></div><div><label for=\"user[description]\"></label>" <>
           "<label for=\"user[description]\"><input checked=\"checked\" " <>
           "name=\"user[description]\" type=\"radio\" value=\"2\">Skill 2</label></div><div>" <>
           "<label for=\"user[description]\"></label><label for=\"user[description]\">" <>
           "<input name=\"user[description]\" type=\"radio\" value=\"3\">Skill 3" <>
           "</label></div></div></div>"
  end

  test "render_field :select" do
    field = %Brando.Form.Field{
      errors: nil,
      form_type: :update,
      name: :description,
      opts: %{
        choices: &UserForm.get_skills_choices/0,
        is_selected: &UserForm.skills_selected?/2,
        action: :update,
        changeset: nil,
        params: "26",
        type: :update,
        label: "Description"
      },
      schema: Brando.User,
      source: "user",
      type: :select,
      value: ["1"]
    }

    assert F.render_field(field).html
           == "<div class=\"form-row\"><div class=\"form-group required\">" <>
           "<label for=\"user[description]\">Description</label>" <>
           "<select name=\"user[description]\"><option selected=\"selected\" value=\"1\">" <>
           "Skill 1</option><option value=\"2\">Skill 2</option><option value=\"3\">Skill 3" <>
           "</option></select></div></div>"
  end
end
