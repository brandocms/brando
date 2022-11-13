defmodule Brando.LivePreviewTest do
  use ExUnit.Case, async: true

  defmodule Layouts do
    use Phoenix.Component

    def app(assigns) do
      ~H|Hello <%= List.first(@employees).name %> :)|
    end
  end

  defmodule TestHTML do
    use Phoenix.Component
    embed_templates "../../fixtures/templates/live_preview_html/*"
  end

  defmodule LivePreview do
    use Brando.LivePreview

    preview_target Brando.Pages.Page do
      template fn e -> {Brando.LivePreviewTest.TestHTML, "#{e.key}.html"} end
      layout {Brando.LivePreviewTest.Layouts, "app"}
      template_section fn entry -> entry.key end

      assign :restaurants, fn _ -> __MODULE__.list_restaurants!() end
      assign :employees, fn _ -> __MODULE__.list_employees!() end
    end

    def list_restaurants! do
      [
        %{id: 1, name: "Oslo"},
        %{id: 2, name: "Bergen"}
      ]
    end

    def list_employees! do
      [
        %{id: 1, name: "Todd"},
        %{id: 2, name: "Rod"}
      ]
    end
  end

  alias Brando.LivePreviewTest.LivePreview

  test "generate render function" do
    assert LivePreview.__info__(:functions) == [
             {:has_preview_target, 1},
             {:list_employees!, 0},
             {:list_restaurants!, 0},
             {:render, 3}
           ]
  end

  test "render function" do
    entry = %{
      id: 1,
      title: "About Us",
      key: "about"
    }

    assert LivePreview.render(Brando.Pages.Page, entry, "MY_CACHE_KEY") ==
             "Hello Todd :)"
  end
end
