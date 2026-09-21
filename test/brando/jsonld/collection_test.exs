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

  describe "Collection.from_entries/2" do
    alias Brando.JSONLD.Collection
    alias Brando.JSONLD.CollectionTest.NoUrlThing
    alias Brando.JSONLD.CollectionTest.Thing

    test "builds an ItemList from entries with a URL and an identifier" do
      entries = [
        %Thing{id: 1, title: "A", slug: "a"},
        %Thing{id: 2, title: "B", slug: "b"}
      ]

      list = Collection.from_entries(entries, type: "CreativeWork")

      assert %ItemList{numberOfItems: 2} = list
      assert [%{position: 1, item: a}, %{position: 2, item: b}] = list.itemListElement
      assert a.name == "A"
      assert a[:"@type"] == "CreativeWork"
      assert String.starts_with?(a.url, "http")
      assert String.ends_with?(a.url, "/things/a")
      assert String.ends_with?(b.url, "/things/b")
    end

    test "plain list items when no type is given" do
      [item] = Collection.from_entries([%Thing{id: 1, title: "A", slug: "a"}]).itemListElement
      assert item.name == "A"
      assert String.ends_with?(item.item, "/things/a")
    end

    test "skips entries without a page of their own" do
      entries = [
        %NoUrlThing{id: 1, title: "no url"},
        %{title: "bare map", slug: "x"},
        %Thing{id: 3, title: "kept", slug: "kept"}
      ]

      list = Collection.from_entries(entries)
      assert list.numberOfItems == 1
      assert [%{name: "kept"}] = list.itemListElement
    end

    test "skips an entry whose URL resolver raises" do
      # The resolver reads `@entry.category.slug`; a missing category raises.
      broken = %Brando.Blueprint.Identifier.HEExTest.HEExAbsoluteURLSchema{id: 1, title: "broken", slug: "b"}
      entries = [broken, %Thing{id: 2, title: "ok", slug: "ok"}]
      list = Collection.from_entries(entries)
      assert [%{name: "ok"}] = list.itemListElement
    end

    test "builds nothing for an empty or fully skipped collection" do
      assert Collection.from_entries([]) == nil
      assert Collection.from_entries([%NoUrlThing{id: 1, title: "x"}]) == nil
      assert Collection.from_entries(nil) == nil
    end

    test "wraps the list in a CollectionPage joined to the site graph" do
      page =
        Collection.from_entries([%Thing{id: 1, title: "A", slug: "a"}],
          type: "Article",
          page: %{url: "/things", language: "no", name: "Things"}
        )

      assert %CollectionPage{name: "Things", inLanguage: "no"} = page
      assert String.ends_with?(page.url, "/things")
      assert String.ends_with?(Map.get(page, :"@id"), "/things/#collectionpage")
      assert %{"@id": website} = page.isPartOf
      assert String.ends_with?(website, "/#website")
      assert %{"@id": identity} = page.publisher
      assert String.ends_with?(identity, "/#identity")
      assert %ItemList{numberOfItems: 1} = page.mainEntity
    end

    test "script/1 renders an inline ld+json tag and nothing for nil" do
      node = Collection.from_entries([%Thing{id: 1, title: "A", slug: "a"}])
      html = node |> Collection.script() |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s(<script type="application/ld+json">)
      assert html =~ ~s("@type":"ItemList")
      assert Phoenix.HTML.safe_to_string(Collection.script(nil)) == ""
    end
  end
end
