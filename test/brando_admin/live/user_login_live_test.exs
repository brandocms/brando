defmodule BrandoAdmin.UserLoginLiveTest do
  use Brando.LiveCase

  # The two Brando marks once both carried Illustrator's `id="Layer_1"`, and
  # LiveView logs a duplicate id as an error in the browser console.
  test "every element id on the login page is unique" do
    {:ok, _view, html} = live(Phoenix.ConnTest.build_conn(), "/admin/login")

    ids = ~r/\sid="([^"]+)"/ |> Regex.scan(html, capture: :all_but_first) |> List.flatten()

    assert ids != []
    assert ids -- Enum.uniq(ids) == []
  end
end
