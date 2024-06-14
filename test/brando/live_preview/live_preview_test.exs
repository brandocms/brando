defmodule Brando.LivePreviewTest do
  use ExUnit.Case, async: true

  test "render function" do
    entry = %{
      id: 1,
      title: "About Us",
      key: "about"
    }

    assert Brando.LivePreview.render(Brando.Pages.Page, entry, "MY_CACHE_KEY") ==
             "<html>\n  <head></head>\n  <body>\n    <div>\n  Hi Todd\n</div><div>\n  Hi Rod\n</div>\n  </body>\n</html>"
  end
end
