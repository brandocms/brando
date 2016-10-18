defmodule Brando.FormTest do
  use ExUnit.Case, async: true
  import Brando.Form

  defmodule MyUser do
    use Brando.Meta.Schema, [
      singular: "user",
      plural: "users",
      repr: &("#{&1.full_name} (#{&1.username})"),
      fields: [
        id: "ID",
        username: "Username",
        email: "Email",
        full_name: "Full name",
        password: "Password",
        role: "Roles",
        language: "Language",
        last_login: "Last login",
        inserted_at: "Inserted at",
        updated_at: "Updated at",
        avatar: "Avatar"
      ],
      fieldsets: [
        permissions: "Permissions",
      ],
      hidden_fields: [:password, :creator],
      help: [
        full_name: "Full name help"
      ]
    ]
  end

  defmodule TestForm do
    use Brando.Form

    form "test", [schema: Brando.FormTest.MyUser, helper: :admin_user_path, class: "grid-form"] do
      fieldset :permissions do
        field :full_name, :text,
          [required: true,
           label: "Fullt navn",
           placeholder: "Fullt navn"]
        field :tags, :text,
          [tags: true]
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

    def get_role_choices() do
      [[value: "1", text: "Staff"],
       [value: "2", text: "Admin"],
       [value: "4", text: "Superuser"]]
    end

    def get_status_choices() do
      [[value: "1", text: "Valg 1"],
       [value: "2", text: "Valg 2"]]
    end

    form "user", [schema: Brando.FormTest.MyUser, helper: :admin_user_path, class: "grid-form"] do
      field :full_name, :text,
        [required: true,
         label: "Full name",
         label_class: "control-label",
         placeholder: "Full name",
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

  test "render_fields/1 :create" do
    form_fields = [
      submit: [type: :submit, text: "Save", class: "btn btn-default"],
      avatar: [type: :file, label: "Avatar"],
      fs123477010: [type: :fieldset_close],
      editor: [type: :checkbox, in_fieldset: 2, label: "Editor", default: true],
      administrator: [type: :checkbox, in_fieldset: 2, label: "Administrator", default: false],
      fs34070328: [type: :fieldset, legend: :rights, row_span: 2],
      status: [type: :select, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
      status2: [type: :select, multiple: true, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
      status3: [type: :radio, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
      status4: [type: :checkbox, multiple: true, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
      email: [type: :email, required: true, label: "E-mail", placeholder: "E-mail"],
      username: [type: :text, required: true, label: "Username", placeholder: "Username"]
    ]

    cs = %{
      action: nil,
      data: nil,
      params: %{},
      errors: [
        username: "has invalid format",
        email: "has invalid format",
        password: "can't be blank",
        email: "can't be blank",
        full_name: "can't be blank",
        username: "can't be blank"
      ]
    }

    form =
      %Brando.Form{
        changeset: cs,
        type: :create,
        source: "user",
        schema: Brando.User,
        fields: form_fields
      } |> render_fields

    html = form.rendered_fields |> Enum.join
    assert html =~ ~s("form-group required")
    assert html =~ "user[username]"
    assert html =~ ~s(placeholder="Username")
    assert html =~ "<legend><br>Rights</legend>"
    assert html =~ ~s(type="submit")
    assert html =~ ~s(type="file")

    cs = %{
      action: :insert,
      data: nil,
      params: nil,
      errors: [
        username: "has invalid format",
        email: "has invalid format",
        password: "can't be blank",
        email: "can't be blank",
        full_name: "can't be blank",
        username: "can't be blank"
      ]
    }

    form =
      form
      |> Map.put(:changeset, cs)
      |> render_fields

    html = form.rendered_fields |> Enum.join
    assert html =~ ~s("form-group required has-error")
    assert html =~ "user[username]"
    assert html =~ ~s(placeholder="Username")
    assert html =~ "<legend><br>Rights</legend>"
    assert html =~ ~s(type="submit")
    assert html =~ ~s(can&#39;t be blank)
    assert html =~ ~s(type="file")
  end

  test "render_fields/1 :update" do
    form_fields = [
      submit: [type: :submit, text: "Save", class: "btn btn-default"],
      avatar: [type: :file, label: "Avatar"],
      fs123477010: [type: :fieldset_close],
      editor: [type: :checkbox, in_fieldset: 2, label: "Editor", default: true],
      administrator: [type: :checkbox, in_fieldset: 2, label: "Administrator", default: false],
      fs34070328: [type: :fieldset, row_span: 2],
      status: [type: :select, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
      status2: [type: :checkbox, multiple: true, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
      status3: [type: :radio, choices: &UserForm.get_status_choices/0, default: "1", label: "Status"],
      email: [type: :email, required: true, label: "E-mail", placeholder: "E-mail"]
    ]

    params = %{
      "avatar" => nil,
      "email" => "test@email.com",
      "role" => 4,
      "full_name" => "Test Name", "id" => 1,
      "inserted_at" => %Ecto.DateTime{day: 7, hour: 4, min: 36, month: 12, sec: 26, year: 2014},
      "last_login" => %Ecto.DateTime{day: 9, hour: 5, min: 2, month: 12, sec: 36, year: 2014},
      "password" => "$2a$12$abcdefghijklmnopqrstuvwxyz",
      "updated_at" => %Ecto.DateTime{day: 14, hour: 21, min: 36, month: 1, sec: 53, year: 2015},
      "username" => "test"
    }

    cs = %{
      action: :insert,
      params: params,
      data: nil,
      errors: []
    }

    form =
      %Brando.Form{
        changeset: cs,
        fields: form_fields,
        type: :update,
        source: "user",
        schema: Brando.User
      } |> render_fields

    html = form.rendered_fields |> Enum.join
    assert html =~ "form-group required"
    assert html =~ "user[email]"
    assert html =~ ~s(value="test@email.com")
    assert html =~ ~s(placeholder="E-mail")
    assert html =~ ~s(type="submit")
    assert html =~ ~s(type="file")
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
