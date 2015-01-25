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
    assert F.__parse_error__(:required) == "Feltet er påkrevet."
    assert F.__parse_error__(:unique) == "Feltet må være unikt. Verdien finnes allerede i databasen."
    assert F.__parse_error__(:format) == "Feltet har feil format."
    assert F.__parse_error__({:too_short, 5}) == "Feltets verdi er for kort. Må være > 5 tegn."
  end
end
