defmodule BrandoAdmin.Components.ShortcutSheetTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.ShortcutSheet

  @registry Path.expand("../../../assets/src/shortcuts/registry.js", __DIR__)

  # The ids and groups in the registry the sheet's rows are drawn from
  defp registry do
    source = File.read!(@registry)

    ids =
      ~r/\{ id: '([a-z-]+)', group: '([a-z]+)'/ |> Regex.scan(source) |> Enum.map(fn [_, id, group] -> {id, group} end)

    [_, groups] = Regex.run(~r/export const GROUPS = \[([^\]]+)\]/, source)
    {ids, ~r/'([a-z]+)'/ |> Regex.scan(groups) |> Enum.map(&List.last/1)}
  end

  test "every shortcut and group in the registry has a label, and no label is left over" do
    {shortcuts, groups} = registry()
    assert length(shortcuts) > 15

    labels = ShortcutSheet.labels()
    keys = Map.keys(labels)

    for {id, _group} <- shortcuts, do: assert(is_binary(labels[id]) and labels[id] != "", "no label for #{id}")
    for group <- groups, do: assert(is_binary(labels["group_" <> group]), "no label for the group #{group}")

    expected = Enum.map(shortcuts, &elem(&1, 0)) ++ Enum.map(groups, &("group_" <> &1))
    leftover = Enum.reject(keys, &(&1 in expected or String.starts_with?(&1, "key_") or &1 in ["then", "or"]))
    assert leftover == []
  end

  test "a dialog named by its title, with the labels for the hook" do
    assigns = %{}
    html = rendered_to_string(~H"<ShortcutSheet.render />")
    [dialog] = html |> Floki.parse_fragment!() |> Floki.find("dialog#shortcut-sheet")

    assert Floki.attribute(dialog, "aria-labelledby") == ["shortcut-sheet-title"]
    assert Floki.attribute(dialog, "phx-hook") == ["Brando.ShortcutSheet"]
    assert [labels] = Floki.attribute(dialog, "data-labels")
    assert Jason.decode!(labels)["go-dashboard"] == "Go to Dashboard"
    assert Floki.find(dialog, "h2#shortcut-sheet-title") != []
    assert Floki.find(dialog, "input[type=checkbox][data-shortcut-sheet-character-keys]") != []
  end
end
