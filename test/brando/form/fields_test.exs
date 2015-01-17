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
    assert F.__form_group__("1234", "name", opts, "err") == "<div class=\"form-group required has-error\">1234</div>"
    assert F.__form_group__("1234", "name", opts, []) == "<div class=\"form-group required\">1234</div>"
    assert F.__form_group__("1234", "name", [], []) == "<div class=\"form-group\">1234</div>"
    opts = [required: false]
    assert F.__form_group__("1234", "name", opts, []) == "<div class=\"form-group\">1234</div>"
    assert F.__form_group__("1234", "name", opts, "err") == "<div class=\"form-group has-error\">1234</div>"
  end
end
