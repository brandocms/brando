defmodule Brando.Form.FieldsTest do
  use ExUnit.Case

  require Brando.Form.Fields, as: F

  @opts [context: Brando.Form.Fields]

  test "__concat__ works" do
    label = "<label>Label</label>"
    wrapped_field = "<div><input /></div>"
    assert F.__concat__(wrapped_field, label) == label <> wrapped_field
  end

  test "__div__ works" do
    assert F.__div__("contents", "class") == "<div class=\"class\">contents</div>"
    assert F.__div__("<b>contents</b>", "class class2") == "<div class=\"class class2\"><b>contents</b></div>"
  end

  test "__form_group__" do
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
end
