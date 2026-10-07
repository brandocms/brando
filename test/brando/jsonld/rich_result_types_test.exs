defmodule Brando.JSONLD.RichResultTypesTest do
  # The graph reads the cached identity.
  use Brando.ConnCase, async: false

  alias Brando.JSONLD.Inspector
  alias Brando.JSONLD.Rules
  alias Brando.JSONLDTest.BookReview
  alias Brando.JSONLDTest.Job
  alias Brando.JSONLDTest.Product
  alias Brando.JSONLDTest.Recipe
  alias Brando.Users.User

  defp image do
    %Brando.Images.Image{
      path: "images/cover.jpg",
      sizes: %{"xlarge" => "images/xlarge/cover.jpg"},
      width: 2100,
      height: 1400
    }
  end

  defp user, do: %User{id: 4, name: "Ada Lovelace", avatar: %Ecto.Association.NotLoaded{}}

  defp graph(module, entry) do
    inspection = Inspector.build(module, entry, language: "en")
    graph = Jason.decode!(inspection.json)["@graph"]
    {graph, inspection}
  end

  defp main(graph, type), do: Enum.find(graph, &(&1["@type"] == type))

  defp lookup(graph) do
    index = Map.new(graph, &{&1["@id"], &1})
    &Map.get(index, &1)
  end

  # Errors are missing properties Google requires; every main entity, and
  # every node the inspector draws, must have none.
  defp refute_errors(inspection) do
    errors = for node <- inspection.nodes, issue <- node.issues, issue.level == :error, do: {node.type, issue.property}
    assert errors == []
  end

  test "Product has a name and an offer with price, currency and availability" do
    product = %Product{
      title: "Kettle",
      slug: "kettle",
      summary: "Boils water.",
      sku: "K-1",
      price: Decimal.new("249.00"),
      in_stock: true,
      rating: 4.6,
      review_count: 31,
      cover: image()
    }

    {graph, inspection} = graph(Product, product)
    node = main(graph, "Product")

    assert node["name"] == "Kettle"
    assert node["image"]["url"] =~ "xlarge/cover.jpg"

    assert node["offers"] == %{
             "@type" => "Offer",
             "price" => "249.00",
             "priceCurrency" => "NOK",
             "availability" => "https://schema.org/InStock"
           }

    assert node["aggregateRating"] == %{"@type" => "AggregateRating", "ratingValue" => 4.6, "reviewCount" => 31}
    assert Rules.validate(node, lookup: lookup(graph)) == []
    refute_errors(inspection)

    # The entry's own nodes: the site's (identity, website, services) depend
    # on whatever identity the cache holds
    entry_types = for %{origin: :entry, type: type} <- inspection.nodes, type != "WebPage", do: type
    assert Enum.sort(entry_types) == ["AggregateRating", "ImageObject", "Offer", "Product"]
  end

  test "Product without an offer, rating or review is an error" do
    {graph, _inspection} = graph(Product, %Product{title: "Kettle", slug: "kettle", cover: image()})
    node = main(graph, "Product")

    # The offer is built from the callback's map, so only the currency is set.
    assert %{"priceCurrency" => "NOK"} = node["offers"]
    assert {:error, "offers.price"} in (node |> Rules.validate() |> Enum.map(&{&1.level, &1.property}))
  end

  test "JobPosting has Google's required properties, with remote work" do
    job = %Job{
      title: "Elixir developer",
      slug: "elixir-developer",
      description: "<p>Build Brando.</p>",
      posted_on: ~D[2026-10-01],
      deadline: ~U[2026-11-01 12:00:00Z],
      salary_from: 650_000,
      salary_to: 800_000
    }

    {graph, inspection} = graph(Job, job)
    node = main(graph, "JobPosting")

    assert %{
             "title" => "Elixir developer",
             "description" => "<p>Build Brando.</p>",
             "datePosted" => "2026-10-01",
             "validThrough" => "2026-11-01T12:00:00Z",
             "employmentType" => "FULL_TIME",
             "jobLocationType" => "TELECOMMUTE",
             "applicantLocationRequirements" => %{"@type" => "Country", "name" => "NO"}
           } = node

    assert node["hiringOrganization"] == %{"@id" => "http://localhost/#identity"}

    assert node["baseSalary"] == %{
             "@type" => "MonetaryAmount",
             "currency" => "NOK",
             "value" => %{
               "@type" => "QuantitativeValue",
               "minValue" => 650_000,
               "maxValue" => 800_000,
               "unitText" => "YEAR"
             }
           }

    assert Rules.validate(node, lookup: lookup(graph)) == []
    refute_errors(inspection)
  end

  test "Recipe has a name and an image, steps as HowToStep and ISO 8601 times" do
    recipe = %Recipe{
      title: "Waffles",
      slug: "waffles",
      summary: "Norwegian heart-shaped waffles.",
      prep_minutes: 15,
      cook_minutes: 25,
      servings: 4,
      ingredients: ["3 eggs", "50 g sugar"],
      steps: ["Whisk the eggs and sugar.", "Bake in a waffle iron."],
      calories: 270,
      cover: image(),
      creator: user(),
      inserted_at: ~N[2026-10-01 08:00:00]
    }

    {graph, inspection} = graph(Recipe, recipe)
    node = main(graph, "Recipe")

    assert %{
             "name" => "Waffles",
             "prepTime" => "PT15M",
             "cookTime" => "PT25M",
             "totalTime" => "PT40M",
             "recipeYield" => "4 servings",
             "recipeIngredient" => ["3 eggs", "50 g sugar"],
             "nutrition" => %{"@type" => "NutritionInformation", "calories" => "270 calories"},
             "datePublished" => "2026-10-01T08:00:00Z"
           } = node

    assert node["image"]["url"] =~ "cover.jpg"

    assert node["recipeInstructions"] == [
             %{"@type" => "HowToStep", "text" => "Whisk the eggs and sugar."},
             %{"@type" => "HowToStep", "text" => "Bake in a waffle iron."}
           ]

    assert %{"@id" => author_id} = node["author"]
    assert %{"@type" => "Person", "name" => "Ada Lovelace"} = Enum.find(graph, &(&1["@id"] == author_id))

    # Only what this recipe can't give is left: a rating, cuisine and the like.
    warnings = node |> Rules.validate(lookup: lookup(graph)) |> Enum.map(& &1.property)
    assert Enum.sort(warnings) == ["aggregateRating", "keywords", "recipeCategory", "recipeCuisine", "video"]
    refute_errors(inspection)
  end

  test "Review names the item, its rating, its author and its date" do
    review = %BookReview{
      title: "A slow, great book",
      slug: "slow-great",
      book_title: "Kristin Lavransdatter",
      verdict: "Worth every page.",
      rating: 5,
      creator: user(),
      inserted_at: ~N[2026-09-30 12:00:00]
    }

    {graph, inspection} = graph(BookReview, review)
    node = main(graph, "Review")

    assert node["itemReviewed"] == %{"@type" => "Book", "name" => "Kristin Lavransdatter"}
    assert node["reviewRating"] == %{"@type" => "Rating", "ratingValue" => 5, "bestRating" => 6, "worstRating" => 1}
    assert node["datePublished"] == "2026-09-30T12:00:00Z"
    assert %{"@id" => _} = node["author"]

    assert Rules.validate(node, lookup: lookup(graph)) == []
    refute_errors(inspection)
  end

  test "a review without what it reviews is an error" do
    {graph, _inspection} = graph(BookReview, %BookReview{title: "Untitled", slug: "u", rating: 3, creator: user()})
    node = main(graph, "Review")

    # A Book with no name says nothing, and is left out.
    refute Map.has_key?(node, "itemReviewed")
    errors = for %{level: :error, property: property} <- Rules.validate(node, lookup: lookup(graph)), do: property
    assert errors == ["itemReviewed"]
  end

  describe "helpers" do
    test "durations become ISO 8601" do
      assert Brando.JSONLD.to_duration(90) == "PT1H30M"
      assert Brando.JSONLD.to_duration("00:45:00") == "PT45M"
      assert Brando.JSONLD.to_duration(Duration.new!(minute: 20)) == "PT20M"
      assert Brando.JSONLD.to_duration("PT20M") == "PT20M"
      assert Brando.JSONLD.to_duration("P") == nil
      assert Brando.JSONLD.to_duration(0) == nil
    end

    test "availabilities are schema.org URLs" do
      assert Brando.JSONLD.Schema.Offer.availability(:pre_order) == "https://schema.org/PreOrder"
      assert Brando.JSONLD.Schema.Offer.availability("InStock") == "https://schema.org/InStock"
      assert Brando.JSONLD.Schema.Offer.availability("https://schema.org/SoldOut") == "https://schema.org/SoldOut"
      assert Brando.JSONLD.Schema.Offer.availability("maybe") == nil
    end
  end
end
