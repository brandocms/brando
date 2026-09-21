defmodule Brando.HTML.ServicesTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Brando.HTML.Services
  alias Brando.Sites.Service

  defp render(assigns) do
    assigns
    |> Map.merge(%{__changed__: %{}})
    |> Map.put_new(:heading, [])
    |> Map.put_new(:item, [])
    |> Map.put_new(:class, nil)
    |> Map.put_new(:language, nil)
    |> Map.put_new(:services, nil)
    |> Services.list()
    |> rendered_to_string()
  end

  test "renders each service with its resolved URL and description" do
    services = [
      %Service{
        name: "Identitetsdesign",
        resolved_url: "https://x.test/id",
        resolved_description: "Vi lager identiteter."
      },
      %Service{name: "Strategi", description: "Own text"}
    ]

    html = render(%{services: services})

    assert html =~ ~s(<section class="services)
    assert html =~ ~s(<a href="https://x.test/id">Identitetsdesign</a>)
    assert html =~ "Vi lager identiteter."
    assert html =~ "<span>Strategi</span>"
    assert html =~ "Own text"
  end

  test "renders nothing when there are no services" do
    assert render(%{services: []}) == ""
    assert render(%{language: "zz"}) == ""
  end

  test "an item slot takes over the entry markup" do
    services = [%Service{name: "X", resolved_url: "https://x.test/x"}]
    item = [%{__slot__: :item, inner_block: fn _, service -> "custom #{service.name}" end}]
    html = render(%{services: services, item: item})

    assert html =~ "custom X"
    refute html =~ "service-name"
  end
end
