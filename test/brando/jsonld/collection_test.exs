defmodule Brando.JSONLD.Schema.CollectionTest do
  use ExUnit.Case, async: true

  alias Brando.JSONLD
  alias Brando.JSONLD.Schema.{CollectionPage, ItemList, Person}

  describe "ItemList" do
    test "numbers positions from one" do
      list = ItemList.build([{"A", "https://x.test/a"}, {"B", "https://x.test/b"}])

      assert list.numberOfItems == 2
      assert [%{position: 1, name: "A"}, %{position: 2, name: "B"}] = list.itemListElement
    end

    test "describes what the entries are when given a type" do
      list = ItemList.build([{"Sommerro", "https://x.test/sommerro", "CreativeWork"}])

      assert [%{item: item, position: 1}] = list.itemListElement
      assert item[:"@type"] == "CreativeWork"
      assert item[:"@id"] == "https://x.test/sommerro/#creativework"
      assert item.url == "https://x.test/sommerro"
    end

    test "an empty collection still encodes as a list, not null" do
      json = JSONLD.to_graph_json([ItemList.build([], name: "Empty")])
      assert %{"@graph" => [node]} = Jason.decode!(json)
      assert node["itemListElement"] == []
      assert node["numberOfItems"] == 0
    end
  end

  describe "CollectionPage" do
    test "joins the graph by reference rather than duplicating nodes" do
      page =
        CollectionPage.build(%{
          id: "https://x.test/work/#collectionpage",
          name: "Work",
          url: "https://x.test/work",
          language: "no",
          is_part_of: "https://x.test/#website",
          about: "https://x.test/#identity",
          publisher: "https://x.test/#identity",
          main_entity: ItemList.build([{"A", "https://x.test/a", "CreativeWork"}])
        })

      assert page.isPartOf == %{"@id": "https://x.test/#website"}
      assert page.about == %{"@id": "https://x.test/#identity"}
      assert page.mainEntity.numberOfItems == 1
    end

    test "encodes without nil keys" do
      json = JSONLD.to_graph_json([CollectionPage.build(%{name: "Work"})])

      refute json =~ "null"
      assert %{"@graph" => [%{"@type" => "CollectionPage", "name" => "Work"}]} = Jason.decode!(json)
    end
  end

  describe "Person" do
    test "carries a job title and links to the organization" do
      person =
        Person.build_person(%{
          id: "https://x.test/#christian",
          name: "Christian Bielke",
          job_title: "Daglig leder",
          email: "christian@x.test",
          works_for: "https://x.test/#identity"
        })

      assert person.jobTitle == "Daglig leder"
      assert person.worksFor == %{"@id": "https://x.test/#identity"}
    end

    test "treats an empty sameAs list as absent" do
      assert Person.build_person(%{name: "X", same_as: []}).sameAs == nil
    end

    test "the old build/1 still works for a bare name" do
      assert Person.build("Christian").name == "Christian"
    end
  end
end
