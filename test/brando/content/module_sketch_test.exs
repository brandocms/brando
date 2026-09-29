defmodule Brando.Content.ModuleSketchTest do
  # What the model returns is rebuilt from an allow-list before it is stored,
  # so a sketch can only draw shapes. (The model itself isn't called here.)
  use ExUnit.Case, async: true

  alias Brando.Content.ModuleSketch

  test "keeps the shapes, in a clean svg with the sketch's viewBox" do
    reply = """
    Here is the sketch:
    ```svg
    <svg width="600" viewBox="0 0 10 10"><rect x="3" y="8" width="22" height="2" rx="1" fill="#9aa8a0"/><g><circle cx="5" cy="5" r="2" fill="#cfd8d2"/></g></svg>
    ```
    """

    assert {:ok, svg} = ModuleSketch.sanitize(reply)

    assert svg ==
             ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 40">) <>
               ~s(<rect x="3" y="8" width="22" height="2" rx="1" fill="#9aa8a0"/>) <>
               ~s(<g><circle cx="5" cy="5" r="2" fill="#cfd8d2"/></g></svg>)
  end

  test "drops scripts, event handlers, links and references" do
    reply =
      ~s|<svg viewBox="0 0 60 40"><script>alert(1)</script><rect x="1" onload="x()" fill="url(#a)" width="4"/>| <>
        ~s|<a href="javascript:x()"><rect width="2"/></a><foreignObject><div/></foreignObject></svg>|

    assert {:ok, svg} = ModuleSketch.sanitize(reply)
    refute svg =~ "script"
    refute svg =~ "onload"
    refute svg =~ "url("
    refute svg =~ "href"
    refute svg =~ "foreignObject"
    assert svg =~ ~s(<rect x="1" width="4"/>)
  end

  test "a reply without a drawable svg is an error" do
    assert {:error, :invalid_response} = ModuleSketch.sanitize("Sorry, I can't draw that.")
    assert {:error, :invalid_response} = ModuleSketch.sanitize(~s(<svg viewBox="0 0 60 40"><text>Hi</text></svg>))
  end
end
