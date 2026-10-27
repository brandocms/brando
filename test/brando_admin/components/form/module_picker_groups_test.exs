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

  test "namespaces stored differently that read the same are one group" do
    modules = [
      %{name: "Slider", namespace: %{"en" => "general"}, sequence: 1},
      %{name: "Text", namespace: "general", sequence: 0},
      %{name: "Image", namespace: %{"en" => "media"}, sequence: 0}
    ]

    groups = ModulePicker.group_by_namespace(modules)

    assert Enum.map(groups, &elem(&1, 0)) |> Enum.sort() == ["general", "media"]
    assert {_, _, [%{name: "Text"}, %{name: "Slider"}]} = List.keyfind(groups, "general", 0)
  end
end
