defmodule BrandoAdmin.Components.Form.ModulePickerGroupsTest do
  # The picker's search looks within the selected group; "Everything" (no
  # group) searches all of them.
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.BlockField.ModulePicker

  defp module(name), do: %{name: name, help_text: nil}

  defp groups do
    [
      {"Media", "media", [module("Image"), module("Image text")]},
      {"Text", "text", [module("Text"), module("Quote")]}
    ]
  end

  test "a search within a group only finds that group's modules" do
    assigns = %{modules_by_namespace: groups(), query: "text", active_namespace: "Text"}
    assert [{"Text", [%{name: "Text"}]}] = ModulePicker.visible_groups(assigns)
  end

  test "without a group, a search finds modules in every group" do
    assigns = %{modules_by_namespace: groups(), query: "text", active_namespace: nil}

    assert [{"Media", [%{name: "Image text"}]}, {"Text", [%{name: "Text"}]}] =
             ModulePicker.visible_groups(assigns)
  end
end
