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

  test "lists the blueprints with a mapping that are not checked, and why" do
    unchecked = StructuredData.unchecked()

    assert {Brando.JSONLDTest.QuietPost, :no_page} in unchecked
    assert {Brando.JSONLDTest.Post, :no_list_function} in unchecked
    # Checked, or without a mapping: not listed
    refute Enum.any?(unchecked, fn {schema, _} -> schema in [Brando.Pages.Page, Brando.Pages.Fragment] end)
    assert unchecked == Enum.uniq(unchecked)
    assert StructuredData.schemas() == Enum.uniq(StructuredData.schemas())
  end

  test "counts the entries checked of each type" do
    products = [
      %Brando.JSONLDTest.Product{id: 1, title: "Kettle", slug: "kettle", sku: "K-1"},
      %Brando.JSONLDTest.Product{id: 2, title: "Teapot", slug: "teapot", sku: "T-1"}
    ]

    put_test_env(Brando.JSONLDTest, products: products, shelves: [])
    result = StructuredData.check("en", [Brando.JSONLDTest.Product, Brando.JSONLDTest.Shelf])

    assert result.per_schema == [{Brando.JSONLDTest.Product, 2}, {Brando.JSONLDTest.Shelf, 0}]
    assert result.checked == 2
  end

  test "a cached result from before the counts per type is run again" do
    user = Factory.insert(:random_user)
    create_page(user, %{title: "First", uri: "first"})

    old = Map.delete(%StructuredData.Result{language: "en", checked: 99}, :per_schema)
    Brando.Cache.put({:seo_structured_data, "en", [Brando.Pages.Page]}, old, :timer.minutes(10))

    assert %{checked: 1, per_schema: [{Brando.Pages.Page, 1}]} = StructuredData.run("en", schemas: [Brando.Pages.Page])
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
      # Its key as well as the image, as a row from the database has: the
      # check loads relations for a page of entries at a time, and Ecto keys
      # an already loaded image by it.
      cover_id: 101,
      cover: %Brando.Images.Image{
        id: 101,
        path: "images/k.jpg",
        sizes: %{"xlarge" => "images/xlarge/k.jpg"},
        width: 9,
        height: 9
      }
    }

    # No image (recommended) and no price (required by the offer)
    incomplete = %Brando.JSONLDTest.Product{id: 2, title: "Teapot", slug: "teapot", summary: "Steeps tea.", sku: "T-1"}
    # Only the image is missing
    imageless = %{complete | id: 3, title: "Mug", slug: "mug", cover_id: nil, cover: nil}

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

  describe "a mapping that reads a relation" do
    alias Brando.Content.Var
    alias Brando.JSONLDTest.Shelf

    setup do
      page = Factory.insert(:page)

      for key <- ["oak", "pine"] do
        Brando.Repo.insert!(%Var{type: :string, key: key, label: %{"en" => key}, page_id: page.id})
      end

      %{page: page}
    end

    # The context lists entries without their relations. The check loads the
    # blueprint's relations a page of entries at a time; before, the field
    # function enumerated a relation that wasn't loaded and the whole check
    # failed.
    test "loads the relations the mapping reads", %{page: page} do
      put_test_env(Brando.JSONLDTest, shelves: [%Shelf{id: page.id, title: "Wood", slug: "wood"}])

      result = StructuredData.check("en", [Shelf])
      assert result.checked == 1
      refute Enum.any?(result.rows, &Enum.any?(&1.issues, fn issue -> issue[:kind] == :build_failed end))
    end

    test "an entry whose graph can't be built is that entry's error, and the rest are still checked", %{page: page} do
      shelves = [
        %Shelf{id: page.id, title: "Wood", slug: "wood"},
        %Shelf{id: page.id + 1, title: "Broken", slug: "broken"},
        %Shelf{id: page.id + 2, title: "Steel", slug: "steel"}
      ]

      put_test_env(Brando.JSONLDTest, shelves: shelves)

      result = StructuredData.check("en", [Shelf])

      assert result.checked == 3
      assert result.with_errors == 1

      assert [%{id: id, title: "Broken", errors: 1, url: "/shelves/broken", issues: [issue]}] =
               Enum.filter(result.rows, &(&1.errors > 0))

      assert id == page.id + 1
      assert %{level: :error, kind: :build_failed, reason: "the shelf has no description"} = issue

      assert BrandoAdmin.Components.Form.StructuredData.describe_issue(issue) ==
               "Could not build structured data: the shelf has no description"
    end
  end
end
