defmodule Brando.Sites.ServicesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Content.Identifier
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Sites
  alias Brando.Sites.Services

  defp identity_for(language) do
    {:ok, identity} = Sites.get_identity(%{matches: %{language: language}, preload: [services: :identifier]})
    identity
  end

  defp page_identifier(page) do
    Brando.Repo.get_by!(Identifier, entry_id: page.id, schema: Pages.Page)
  end

  test "a linked page supplies the URL and description, and the cache resolves it once" do
    user = Factory.insert(:random_user)

    {:ok, page} =
      Pages.create_page(
        %{
          title: "Identitetsdesign",
          uri: "identitetsdesign",
          language: "en",
          template: "default.html",
          status: :published,
          meta_description: "Vi utvikler visuelle identiteter."
        },
        user
      )

    identifier = page_identifier(page)
    identity = identity_for("en")

    {:ok, _} =
      Sites.update_identity(
        identity,
        %{services: [%{name: "Identitetsdesign", identifier_id: identifier.id, alternate_names: ["Brand identity", ""]}]},
        user
      )

    [service] = Brando.Cache.Identity.get("en").services

    assert service.resolved_description == "Vi utvikler visuelle identiteter."
    assert String.starts_with?(service.resolved_url, "http")
    assert String.ends_with?(service.resolved_url, "/identitetsdesign")
    assert service.alternate_names == ["Brand identity"]
  end

  test "builds Service nodes joined to the identity, inheriting its markets" do
    identity = %Sites.Identity{
      type_config: %Sites.Identity.TypeConfig{area_served: ["Norway"]},
      services: [
        %Sites.Service{name: "Identitetsdesign", resolved_url: "https://x.test/id", resolved_description: "Desc"},
        %Sites.Service{name: "Strategi", area_served: ["Worldwide"], service_type: "Consulting", url: "/strategi"}
      ]
    }

    [a, b] = Services.to_json_ld(identity)

    assert a.name == "Identitetsdesign"
    assert String.ends_with?(a."@id", "/#service-identitetsdesign")
    assert %{"@id": provider} = a.provider
    assert String.ends_with?(provider, "/#identity")
    assert a.areaServed == ["Norway"]
    assert a.url == "https://x.test/id"
    assert a.description == "Desc"

    assert b.areaServed == ["Worldwide"]
    assert b.serviceType == "Consulting"
    assert String.ends_with?(b.url, "/strategi")
    assert String.starts_with?(b.url, "http")
  end

  test "an identity without loaded services builds nothing" do
    assert Services.to_json_ld(%Sites.Identity{}) == []
    assert Services.to_json_ld(%{}) == []
  end

  test "resolve keeps an explicit description and URL over the linked page's" do
    service = %Sites.Service{name: "X", description: "Own", url: "https://own.test/x", identifier: nil}
    resolved = Services.resolve(service)
    assert resolved.resolved_description == "Own"
    assert resolved.resolved_url == "https://own.test/x"
  end

  test "the page picker lists identifiers that have a URL" do
    user = Factory.insert(:random_user)

    {:ok, page} =
      Pages.create_page(
        %{title: "Picked", uri: "picked", language: "en", template: "default.html", status: :published},
        user
      )

    identifier = page_identifier(page)

    options = Services.identifier_options(nil, [])
    assert Enum.any?(options, &(&1.value == identifier.id and &1.label =~ "Picked"))
  end
end
