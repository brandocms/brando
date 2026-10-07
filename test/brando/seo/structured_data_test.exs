defmodule Brando.SEO.StructuredDataTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.SEO.StructuredData

  defp create_page(user, attrs) do
    {:ok, page} =
      Pages.create_page(
        Map.merge(%{language: "en", template: "default.html", status: :published}, attrs),
        user
      )

    page
  end

  setup do
    on_exit(fn -> Brando.Cache.del({:seo_structured_data, "en", [Brando.Pages.Page]}) end)
    :ok
  end

  test "checks blueprints with a JSON-LD mapping and a page of their own" do
    schemas = StructuredData.schemas()

    assert Brando.Pages.Page in schemas
    # No page of its own
    refute Brando.Pages.Fragment in schemas
    # A test blueprint without a context to list it from
    refute Brando.JSONLDTest.Post in schemas
  end

  test "counts entries with errors and warnings, leaving the site's identity out" do
    complete = %Brando.JSONLDTest.Product{
      id: 1,
      title: "Kettle",
      slug: "kettle",
      summary: "Boils water.",
      sku: "K-1",
      price: Decimal.new("249"),
      in_stock: true,
      cover: %Brando.Images.Image{path: "images/k.jpg", sizes: %{"xlarge" => "images/xlarge/k.jpg"}, width: 9, height: 9}
    }

    # No image (recommended) and no price (required by the offer)
    incomplete = %Brando.JSONLDTest.Product{id: 2, title: "Teapot", slug: "teapot", summary: "Steeps tea.", sku: "T-1"}
    # Only the image is missing
    imageless = %{complete | id: 3, title: "Mug", slug: "mug", cover: nil}

    put_test_env(Brando.JSONLDTest, products: [complete, incomplete, imageless])
    result = StructuredData.check("en", [Brando.JSONLDTest.Product])

    assert result.checked == 3
    assert result.with_errors == 1
    assert result.with_warnings == 1
    assert is_integer(result.duration_ms)

    assert [teapot, mug] = result.rows

    assert %{id: 2, title: "Teapot", type: "Product", errors: 1, warnings: 1, url: "http://localhost/shop/teapot"} =
             teapot

    assert [{:error, "offers.price"}, {:warning, "image"}] =
             teapot.issues |> Enum.map(&{&1.level, &1.property}) |> Enum.sort()

    assert %{id: 3, errors: 0, warnings: 1} = mug
    refute Enum.any?(result.rows, &(&1.id == 1))
  end

  test "pages are checked in the language, published only" do
    user = Factory.insert(:random_user)
    create_page(user, %{title: "Published", uri: "published"})
    create_page(user, %{title: "Draft", uri: "draft", status: :draft})
    create_page(user, %{title: "Norsk", uri: "norsk", language: "no"})

    assert %{checked: 1} = StructuredData.check("en", [Brando.Pages.Page])
  end

  test "keeps the result for a while, and runs again on request" do
    user = Factory.insert(:random_user)
    create_page(user, %{title: "First", uri: "first"})

    first = StructuredData.run("en", schemas: [Brando.Pages.Page])
    assert first.checked == 1

    create_page(user, %{title: "Second", uri: "second"})

    assert StructuredData.run("en", schemas: [Brando.Pages.Page]) == first
    assert StructuredData.run("en", schemas: [Brando.Pages.Page], refresh: true).checked == 2
  end
end
