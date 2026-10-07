defmodule Brando.JSONLD.RulesTest do
  use ExUnit.Case, async: true

  alias Brando.JSONLD.Rules

  defp issues(node, opts \\ []), do: node |> Rules.validate(opts) |> Enum.map(&{&1.level, &1.property, &1.kind})
  defp errors(node, opts \\ []), do: for({:error, property, _} <- issues(node, opts), do: property)
  defp warnings(node, opts \\ []), do: for({:warning, property, _} <- issues(node, opts), do: property)

  describe "Article" do
    test "has no required properties and recommends Google's list" do
      assert errors(%{"@type" => "Article"}) == []

      assert warnings(%{"@type" => "Article"}) == [
               "author",
               "author.name",
               "author.url | author.sameAs",
               "datePublished",
               "dateModified",
               "headline",
               "image"
             ]
    end

    test "follows the author's @id to the Person node" do
      people = %{"https://e.x/#ada" => %{"@type" => "Person", "name" => "Ada", "sameAs" => ["https://x.test/ada"]}}

      article = %{
        "@type" => "BlogPosting",
        "author" => %{"@id" => "https://e.x/#ada"},
        "headline" => "On engines",
        "image" => %{"@type" => "ImageObject", "url" => "https://e.x/a.jpg"},
        "datePublished" => "2026-10-01T10:00:00Z",
        "dateModified" => "2026-10-02"
      }

      assert issues(article, lookup: &Map.get(people, &1)) == []
      assert "author.name" in warnings(article)
    end

    test "flags values Google can't read" do
      article = %{
        "@type" => "Article",
        "headline" => " ",
        "datePublished" => "01.10.2026",
        "url" => "/news/a",
        "image" => %{"@type" => "ImageObject", "url" => "/media/a.jpg"}
      }

      found = issues(article)
      assert {:warning, "headline", :empty} in found
      assert {:warning, "datePublished", :invalid_date} in found
      assert {:warning, "url", :relative_url} in found
      assert {:warning, "image.url", :relative_url} in found
    end
  end

  describe "Product and Offer" do
    test "require a name and one of offers, review or aggregateRating" do
      assert errors(%{"@type" => "Product"}) == ["name", "offers | review | aggregateRating"]
      rating = %{"@type" => "AggregateRating", "ratingValue" => 4.5, "reviewCount" => 12}
      assert errors(%{"@type" => "Product", "name" => "Kettle", "aggregateRating" => rating}) == []

      # A nested review is checked as one, prefixed with where it sits.
      assert "review[0].reviewRating" in errors(%{
               "@type" => "Product",
               "name" => "Kettle",
               "review" => [%{"@type" => "Review"}]
             })
    end

    test "an offer needs a price and a currency, and an availability Google reads" do
      product = %{
        "@type" => "Product",
        "name" => "Kettle",
        "offers" => %{"@type" => "Offer", "price" => "two hundred", "availability" => "in stock"}
      }

      found = issues(product)
      assert {:error, "offers.priceCurrency", :missing} in found
      assert {:warning, "offers.price", :invalid_value} in found
      assert {:warning, "offers.availability", :invalid_value} in found

      # Drawn as a node of its own in the inspector, an offer is checked there.
      assert issues(product, skip_nested: ["Offer"]) |> Enum.filter(&String.starts_with?(elem(&1, 1), "offers")) == []
    end

    test "an aggregate rating needs a value and a count" do
      assert errors(%{"@type" => "AggregateRating", "ratingValue" => 4.4}) == ["ratingCount | reviewCount"]
      assert errors(%{"@type" => "AggregateRating", "ratingValue" => 4.4, "reviewCount" => 9}) == []
    end
  end

  describe "JobPosting" do
    test "requires Google's properties, and a location or remote work" do
      assert errors(%{"@type" => "JobPosting"}) == [
               "title",
               "description",
               "datePosted",
               "hiringOrganization",
               "jobLocation | jobLocationType"
             ]

      assert warnings(%{"@type" => "JobPosting"}) == ["validThrough", "employmentType", "baseSalary"]
    end

    test "a remote job needs where applicants may live" do
      job = %{
        "@type" => "JobPosting",
        "title" => "Developer",
        "description" => "<p>Elixir</p>",
        "datePosted" => "2026-10-01",
        "hiringOrganization" => %{"@id" => "https://e.x/#identity"},
        "jobLocationType" => "TELECOMMUTE",
        "employmentType" => "SOMETIMES"
      }

      assert errors(job) == ["applicantLocationRequirements"]
      assert {:warning, "employmentType", :invalid_value} in issues(job)
      assert errors(Map.put(job, "applicantLocationRequirements", %{"@type" => "Country", "name" => "NO"})) == []
    end
  end

  describe "Recipe" do
    test "requires a name and an image, and ISO 8601 times" do
      assert errors(%{"@type" => "Recipe"}) == ["name", "image"]

      recipe = %{"@type" => "Recipe", "name" => "Waffles", "image" => "https://e.x/w.jpg", "totalTime" => "40 min"}
      assert errors(recipe) == []
      assert {:warning, "totalTime", :invalid_duration} in issues(recipe)
      assert "nutrition.calories" in warnings(recipe)
    end
  end

  describe "Review" do
    test "needs what it reviews on its own, but not inside a product" do
      review = %{
        "@type" => "Review",
        "author" => %{"@type" => "Person", "name" => "Ada"},
        "reviewRating" => %{"@type" => "Rating", "ratingValue" => 5}
      }

      assert errors(review) == ["itemReviewed"]
      assert errors(review, standalone: false) == []
      assert errors(Map.delete(review, "reviewRating"), standalone: false) == ["reviewRating", "reviewRating.ratingValue"]
    end
  end

  describe "VideoObject, BreadcrumbList, Organization, ProfilePage, Event" do
    test "a video needs a name, a thumbnail and an upload date" do
      assert errors(%{"@type" => "VideoObject"}) == ["name", "thumbnailUrl", "uploadDate"]
      assert warnings(%{"@type" => "VideoObject"}) == ["description", "duration", "contentUrl | embedUrl"]

      assert {:warning, "duration", :invalid_duration} in issues(%{"@type" => "VideoObject", "duration" => "01:30"})
    end

    test "breadcrumb items need a position and a name, and absolute URLs" do
      list = %{
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          %{"@type" => "ListItem", "position" => 1, "name" => "Home", "item" => "https://e.x/"},
          %{"@type" => "ListItem", "position" => 2, "item" => "/news"}
        ]
      }

      found = issues(list)
      assert {:error, "itemListElement[1].name", :missing} in found
      assert {:warning, "itemListElement[1].item", :relative_url} in found
      assert errors(%{"@type" => "BreadcrumbList"}) == ["itemListElement"]
    end

    test "an organization has recommendations only; a local business needs an address" do
      assert errors(%{"@type" => "Corporation"}) == []
      assert "logo" in warnings(%{"@type" => "Corporation"})
      assert errors(%{"@type" => "Restaurant", "name" => "Fisk"}) == ["address"]
    end

    test "a profile page needs its person's name" do
      people = %{"https://e.x/ada/#person" => %{"@type" => "Person"}}
      page = %{"@type" => "ProfilePage", "mainEntity" => %{"@id" => "https://e.x/ada/#person"}}

      assert errors(page, lookup: &Map.get(people, &1)) == ["mainEntity.name"]
    end

    test "an event needs a name, a start date and a location" do
      assert errors(%{"@type" => "ExhibitionEvent"}) == ["name", "startDate", "location"]
    end

    test "types without a rich result are checked for their values only" do
      assert issues(%{"@type" => "WebSite"}) == []
      assert issues(%{"@type" => "WebPage", "url" => "/a"}) == [{:warning, "url", :relative_url}]
    end
  end

  test "properties lists a type's rules at the top level" do
    assert Rules.properties("Review") == [
             {"author", :required},
             {"reviewRating", :required},
             {"itemReviewed", :required},
             {"datePublished", :recommended}
           ]

    assert {"itemReviewed", :required} not in Rules.properties("Review", standalone: false)
    assert Rules.properties("WebSite") == []
  end
end
