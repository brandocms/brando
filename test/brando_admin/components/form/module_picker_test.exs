defmodule BrandoAdmin.Components.Form.BlockField.ModulePickerTest do
  # The picker's list: recently used modules first (and out of their own
  # groups) until you search or pick a group, and an icon for modules without
  # a sketch, read from what they hold.
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.BlockField.ModulePicker

  defp module(id, name, refs \\ []),
    do: %{
      id: id,
      library_origin: :local,
      name: %{"en" => name},
      help_text: nil,
      refs: refs,
      datasource: false,
      multi: false
    }

  defp ref(type), do: %{data: %{type: type}}

  setup do
    text = module(1, "Body text", [ref("text")])
    quote_module = module(2, "Quote", [ref("text")])
    picture = module(3, "Picture", [ref("picture")])

    %{
      assigns: %{
        modules_by_namespace: [{"Text", %{}, [text, quote_module]}, {"Media", %{}, [picture]}],
        recent_ids: ["local:3", "local:99"],
        active_namespace: nil,
        query: ""
      }
    }
  end

  test "recently used come first and leave their group", %{assigns: assigns} do
    assert [{"Recently used", [%{id: 3}]}, {"Text", [%{id: 1}, %{id: 2}]}] = ModulePicker.visible_groups(assigns)
  end

  test "a search shows every match in its own group", %{assigns: assigns} do
    assert [{"Media", [%{id: 3}]}] = ModulePicker.visible_groups(%{assigns | query: "pict"})
  end

  test "the recently used entry shows only those", %{assigns: assigns} do
    assert [{"Recently used", [%{id: 3}]}] = ModulePicker.visible_groups(%{assigns | active_namespace: "__recent"})
  end

  test "icons follow what a module holds" do
    assert ModulePicker.module_icon(module(1, "a", [ref("header"), ref("text")])) == "hero-bars-3-bottom-left"
    assert ModulePicker.module_icon(module(1, "a", [ref("gallery")])) == "hero-squares-2x2"
    assert ModulePicker.module_icon(module(1, "a", [ref("picture"), ref("text")])) == "hero-photo"
    assert ModulePicker.module_icon(%{module(1, "a") | datasource: true}) == "hero-queue-list"
    assert ModulePicker.module_icon(%{module(1, "a") | multi: true}) == "hero-rectangle-stack"
    assert ModulePicker.module_icon(%{id: 1, refs: %Ecto.Association.NotLoaded{}}) == "hero-cube"
  end
end
