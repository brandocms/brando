defmodule Brando.Blueprint.Identifier.GeneratorTest do
  use ExUnit.Case

  alias Brando.Blueprint.Identifier.Generator
  alias Brando.Pages.Page

  describe "extract_cover/2" do
    test "returns nil when field is nil" do
      assert Generator.extract_cover(nil, %{}) == nil
    end

    test "returns nil when entry is nil" do
      assert Generator.extract_cover(%{name: :cover}, nil) == nil
    end

    test "returns nil when cover field is nil" do
      entry = %{cover: nil}
      assert Generator.extract_cover(%{name: :cover}, entry) == nil
    end

    test "extracts cover URL from image field" do
      entry = %{
        cover: %Brando.Images.Image{
          path: "/dummy/image.jpg",
          sizes: %{
            "thumb" => "/dummy/thumb/image.jpg",
            "medium" => "/dummy/medium/image.jpg"
          }
        }
      }

      result = Generator.extract_cover(%{name: :cover}, entry)
      assert result =~ "/thumb/"
    end
  end

  describe "generate/4" do
    test "generates identifier from page entry" do
      {:ok, parsed} = Liquex.parse("{{ entry.title }}", Brando.Villain.LiquexParser)

      entry = %Page{
        id: 1,
        title: "Test Page",
        status: :published,
        language: :en,
        uri: "test-page"
      }

      result = Generator.generate(Page, entry, parsed, [])

      assert result.entry_id == 1
      assert result.title == "Test Page"
      assert result.status == :published
      assert result.language == :en
      assert result.schema == Page
    end

    test "handles skip_cover option" do
      {:ok, parsed} = Liquex.parse("{{ entry.title }}", Brando.Villain.LiquexParser)

      entry = %Page{
        id: 1,
        title: "Test Page",
        status: :published,
        language: :en,
        uri: "test-page"
      }

      result = Generator.generate(Page, entry, parsed, skip_cover: true)
      assert result.cover == nil
    end

    test "handles string language" do
      {:ok, parsed} = Liquex.parse("{{ entry.title }}", Brando.Villain.LiquexParser)

      entry = %Page{
        id: 1,
        title: "Test Page",
        status: :published,
        language: "en",
        uri: "test-page"
      }

      result = Generator.generate(Page, entry, parsed, [])
      assert result.language == :en
    end

    test "handles nil language" do
      {:ok, parsed} = Liquex.parse("{{ entry.title }}", Brando.Villain.LiquexParser)

      entry = %{
        __struct__: Page,
        id: 1,
        title: "Test Page",
        status: :published,
        language: nil,
        uri: "test-page"
      }

      result = Generator.generate(Page, entry, parsed, [])
      assert result.language == nil
    end
  end
end
