defmodule Brando.Form.FieldsTest do
  use ExUnit.Case, async: true

  require Brando.Form.Fields, as: F

  @opts [context: Brando.Form.Fields]

  test "__concat__/2" do
    label = "<label>Label</label>"
    wrapped_field = "<div><input /></div>"
    assert F.__concat__(wrapped_field, label) == label <> wrapped_field
  end

  test "__div__/2" do
    assert F.__div__("contents", "class") == "<div class=\"class\">contents</div>"
    assert F.__div__("<b>contents</b>", "class class2") == "<div class=\"class class2\"><b>contents</b></div>"
  end

  test "__form_group__/4" do
    opts = [required: true]
    fg = F.__form_group__("1234", "name", opts, [:required])
    assert String.contains?(fg, "required")
    assert String.contains?(fg, "has-error")
    assert String.contains?(fg, "fa-exclamation-circle")

    fg = F.__form_group__("1234", "name", opts, [])
    assert String.contains?(fg, "required")
    refute String.contains?(fg, "has-error")

    fg = F.__form_group__("1234", "name", [], [])
    refute String.contains?(fg, "required")
    refute String.contains?(fg, "has-error")

    opts = [required: false]
    fg = F.__form_group__("1234", "name", opts, [])
    refute String.contains?(fg, "required")
    refute String.contains?(fg, "has-error")

    fg = assert F.__form_group__("1234", "name", opts, [:unique])
    assert String.contains?(fg, "has-error")
    assert String.contains?(fg, "fa-exclamation-circle")
  end

  test "__tag__/4" do
    assert F.__tag__("select", "name", "test", "class") == "<select name=\"name\" class=\"class\">test</select>"
  end

  test "__wrap__/2" do
    assert F.__wrap__("test", nil) == "test"
    assert F.__wrap__("test", "wrapper_class") == "<div class=\"wrapper_class\">test</div>"
  end

  test "__parse_error__/1" do
    assert F.__parse_error__("can't be blank") == "Feltet er påkrevet."
    assert F.__parse_error__("must be unique") == "Feltet må være unikt. Verdien finnes allerede i databasen."
    assert F.__parse_error__("has invalid format") == "Feltet har feil format."
    assert F.__parse_error__({"should be at least %{count} characters", 5}) == "Feltets verdi er for kort. Må være > 5 tegn."
  end

  test "__textarea__/5" do
    assert F.__textarea__(:create, "name", [], nil, []) == ~s(<textarea name="name"></textarea>)
    assert F.__textarea__(:update, "name", "blah", nil, []) == ~s(<textarea name="name">blah</textarea>)
    assert F.__textarea__(:update, "name", "blah", nil, [default: "default"]) == ~s(<textarea name="name">blah</textarea>)
    assert F.__textarea__(:update, "name", [], nil, [default: "default"]) == ~s(<textarea name="name">default</textarea>)
    assert F.__textarea__(:update, "name", [], nil, [default: "default", class: "class"]) == ~s(<textarea name="name" class="class">default</textarea>)
  end

  test "__file__/4" do
    assert F.__file__(:update, "user[avatar]", %{sizes: %{thumb: "images/default/thumb/0.jpeg"}},
                      [], [type: :file, label: "Bilde"]) == "<div class=\"image-preview\"><img src=\"images/default/thumb/0.jpeg\" /></div><input name=\"user[avatar]\" type=\"file\" />"
  end

  test "get_form_group_class/1" do
    assert F.get_form_group_class(nil) == ""
    assert F.get_form_group_class("test") == " test"
  end

  test "get_slug_from/2" do
    assert F.get_slug_from("testform[title]", []) == ""
    assert F.get_slug_from("testform[title]", [slug_from: :name]) ==
      ~s( data-slug-from="testform[name]")
  end

  test "__input__ checkbox" do
    assert F.__input__(:checkbox, :create, "name", [], [], []) ==
      "<input name=\"name\" type=\"checkbox\" />"
    assert F.__input__(:checkbox, :create, "name", false, [], []) ==
      "<input name=\"name\" type=\"checkbox\" />"
    assert F.__input__(:checkbox, :create, "name", nil, [], []) ==
      "<input name=\"name\" type=\"checkbox\" />"
    assert F.__input__(:checkbox, :create, "name", true, [], []) ==
      "<input name=\"name\" type=\"checkbox\" checked=\"checked\" />"
    assert F.__input__(:checkbox, :create, "name", "on", [], []) ==
      "<input name=\"name\" type=\"checkbox\" checked=\"checked\" />"

  end
end
