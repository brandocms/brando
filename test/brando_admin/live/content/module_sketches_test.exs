defmodule BrandoAdmin.Content.ModuleSketchesTest do
  # The "Sketches with AI" dialog while it runs: progress, a check and the new
  # sketch on drawn rows, the error on failed ones, the one being drawn marked.
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Content.ModuleListLive

  @svg ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 40"><rect width="4" height="4"/></svg>)

  defp module(id, name), do: %{id: id, name: %{"en" => name}}

  test "shows each module's state and the sketches as they arrive" do
    html =
      render_component(&ModuleListLive.sketches/1,
        sketches: %{
          available?: true,
          missing: [module(1, "Body text"), module(2, "Quote"), module(3, "Slider"), module(4, "Credits")],
          running?: true,
          current: 3,
          drawn: %{1 => @svg},
          failed: [{2, "The AI reply could not be read"}]
        }
      )

    assert html =~ ~s(class="is-done")
    assert html =~ "data:image/svg+xml;base64," <> Base.encode64(@svg)
    assert html =~ "The AI reply could not be read"
    assert html =~ ~s(class="is-current")
    assert html =~ ~s(class="pending")
    assert html =~ "width: 50%"
    assert html =~ "Drawing 3 of 4"
  end

  test "says so when every module has a sketch" do
    html =
      render_component(&ModuleListLive.sketches/1,
        sketches: %{available?: true, missing: [], running?: false, current: nil, drawn: %{}, failed: []}
      )

    assert html =~ "Every module has a sketch."
    refute html =~ "module-sketches-actions"
  end
end
