defmodule Brando.JSONLD.Schema.ServiceTest do
  use ExUnit.Case, async: true

  alias Brando.JSONLD
  alias Brando.JSONLD.Schema.Service

  @provider "https://example.com/#identity"

  test "builds a node that joins the graph by reference" do
    service =
      Service.build(%{
        id: "https://example.com/#identity-design",
        name: "Identitetsdesign",
        provider: @provider
      })

    assert service."@type" == "Service"
    assert service."@id" == "https://example.com/#identity-design"
    assert service.provider == %{"@id": @provider}
  end

  test "passes a provider map through untouched" do
    provider = %{"@type": "Organization", name: "Example"}
    assert Service.build(%{name: "X", provider: provider}).provider == provider
  end

  test "carries the other language's phrasing in alternateName" do
    service =
      Service.build(%{
        name: "Identitetsdesign",
        alternate_names: ["Brand Identity Design", "visuell identitet"]
      })

    assert service.alternateName == ["Brand Identity Design", "visuell identitet"]
  end

  test "treats an empty alternate name list as absent so it slims away" do
    assert Service.build(%{name: "X", alternate_names: []}).alternateName == nil
    assert Service.build(%{name: "X"}).alternateName == nil
  end

  test "build_all applies shared defaults without overriding per-service values" do
    services =
      Service.build_all(
        [
          %{id: "https://example.com/#a", name: "A"},
          %{id: "https://example.com/#b", name: "B", area_served: "Norge"}
        ],
        provider: @provider,
        area_served: "Worldwide"
      )

    assert [a, b] = services
    assert a.provider == %{"@id": @provider}
    assert a.areaServed == "Worldwide"
    assert b.areaServed == "Norge"
  end

  test "encodes without nil keys once it reaches the graph" do
    json =
      JSONLD.to_graph_json([
        Service.build(%{id: "https://example.com/#a", name: "A", provider: @provider})
      ])

    decoded = Jason.decode!(json)

    assert [node] = decoded["@graph"]

    assert node == %{
             "@type" => "Service",
             "@id" => "https://example.com/#a",
             "name" => "A",
             "provider" => %{"@id" => @provider}
           }

    refute json =~ "null"
    # @context belongs to the document, not the node
    refute Map.has_key?(node, "@context")
  end
end
