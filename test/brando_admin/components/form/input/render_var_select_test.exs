defmodule BrandoAdmin.Components.Form.Input.RenderVarSelectTest do
  # A select var's choices are typed in the module editor by another admin.
  # The select renders option labels as markup, so they arrive escaped.
  use ExUnit.Case, async: true

  alias Brando.Content.Var
  alias BrandoAdmin.Components.Form.Input.RenderVar

  test "option labels are escaped" do
    label = ~s(<img src="data:," onerror="document.title=1">Small)

    # A string: a `{:safe, _}` label would go into `data-select-label`
    # unescaped, and the browser would decode it back to markup.
    assert [%{label: escaped, value: "s"}] =
             RenderVar.select_options([%Var.Option{label: %{"en" => label, "no" => label}, value: "s"}])

    assert is_binary(escaped)
    assert escaped =~ "&lt;img"
    refute escaped =~ "<img"
  end
end
