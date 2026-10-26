defmodule BrandoAdmin.Components.Form.Input.RenderVarSelectTest do
  # A select var's choices are typed in the module editor by another admin.
  # Select escapes option labels itself (OptionLabelsTest), so they arrive as
  # plain strings: escaping them here as well would show `&lt;` to editors.
  use ExUnit.Case, async: true

  alias Brando.Content.Var
  alias BrandoAdmin.Components.Form.Input.RenderVar

  test "option labels arrive as plain strings, for Select to escape once" do
    label = ~s(<img src="data:," onerror="document.title=1">Small & co)

    # A string, not `{:safe, _}`: Select treats a safe tuple as markup.
    assert [%{label: ^label, value: "s"}] =
             RenderVar.select_options([%Var.Option{label: %{"en" => label, "no" => label}, value: "s"}])
  end
end
