defmodule BrandoAdmin.Components.Form.HiddenI18nTest do
  # A var carries its label (a language map) through the block form while it
  # is unsaved: one hidden input per language, so the map posts back whole.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BrandoAdmin.Components.Form.Input

  defp field(value),
    do: %Phoenix.HTML.FormField{id: "var_label", name: "var[label]", value: value, field: :label, form: nil, errors: []}

  test "a language map goes as one input per language" do
    html = render_component(&Input.hidden_i18n/1, field: field(%{"no" => "Størrelse", "en" => "Size"}))

    assert html =~ ~s(name="var[label][en]" value="Size")
    assert html =~ ~s(name="var[label][no]" value="Størrelse")
  end

  test "a plain string goes as one input" do
    assert render_component(&Input.hidden_i18n/1, field: field("Size")) =~ ~s(name="var[label]" value="Size")
  end
end
