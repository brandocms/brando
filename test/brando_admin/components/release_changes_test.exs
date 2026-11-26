defmodule BrandoAdmin.Components.ReleaseChangesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.ReleaseChanges

  defp row(uid, children),
    do: %{uid: uid, namespace: "02 Media", title: "Image", children: children, status: :update}

  defp confirm(rows) do
    render_component(&ReleaseChanges.confirm/1,
      open?: true,
      rows: rows,
      keep_here: [],
      excluded: [],
      failures: 0,
      entries: Map.new(rows, &{&1.uid, %{count: 2, live: 1}})
    )
  end

  defp names(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("#release-confirm li > span:first-child")
    |> Enum.map(&Floki.text/1)
  end

  test "the apply dialog names a module without children by its name alone, and counts the children of one with" do
    html = confirm([row("a", []), row("b", ["Caption", "Credit"])])

    assert names(html) == ["02 Media › Image", "02 Media › Image + 2"]
  end
end
