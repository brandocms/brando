defmodule Brando.LivePreviewTest do
  use ExUnit.Case, async: true

  defmodule LayoutView do
    use Phoenix.View, root: "test/templates"

    def render("app.html", assigns) do
      {:safe, "Hello #{List.first(assigns.employees).name} :)"}
    end
  end

  defmodule TestView do
    use Phoenix.View, root: "test/templates"
  end

  defmodule LivePreview do
    use Brando.LivePreview

    target(
      schema_module: Brando.Pages.Page,
      view_module: Brando.LivePreviewTest.TestView,
      layout_module: Brando.LivePreviewTest.LayoutView,
      layout_template: "app.html",
      template: fn entry -> "#{entry.key}.html" end,
      section: fn entry -> entry.key end
    ) do
      assign :restaurants, fn -> __MODULE__.list_restaurants!() end
      assign :employees, fn -> __MODULE__.list_employees!() end
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
             {:list_employees!, 0},
             {:list_restaurants!, 0},
             {:render, 5}
           ]
  end

  test "render function" do
    entry = %{
      id: 1,
      title: "About Us",
      key: "about"
    }

    assert LivePreview.render(Brando.Pages.Page, entry, nil, "page", "MY_CACHE_KEY") ==
             "Hello Todd :)"
  end
end
