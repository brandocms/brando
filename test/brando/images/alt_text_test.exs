defmodule Brando.Images.AltTextTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Images.AltText
  alias Brando.Images.Image
  alias Brando.SEO.Suggestions

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)

  # The factory gives every image the same size paths; tests that place
  # files on disk need their own, or one test's file answers for another's.
  defp insert_image(attrs) do
    Factory.insert(:image, Map.merge(%{status: :processed, alt: nil, sizes: sizes(attrs[:path])}, attrs))
  end

  defp sizes(path) do
    base = Path.rootname(path)
    Map.new(~w(thumb small medium large xlarge), &{&1, "#{base}/#{&1}.jpg"})
  end

  # Puts the fixture where the image's rendition is read from.
  defp place_file(image) do
    target = Path.join(Brando.Tenant.Storage.current_media_root(), AltText.rendition(image))
    File.mkdir_p!(Path.dirname(target))
    File.cp!(@fixture, target)
  end

  test "lists images missing alt text in any content language, leaving out SVGs and deleted ones" do
    bare = insert_image(%{path: "images/alt/bare.jpg"})
    blank = insert_image(%{path: "images/alt/blank.jpg", alt: %{"en" => "  "}})
    half = insert_image(%{path: "images/alt/half.jpg", alt: %{"en" => "A ferry"}})
    insert_image(%{path: "images/alt/done.jpg", alt: %{"en" => "A ferry", "no" => "En ferje"}})
    insert_image(%{path: "images/alt/logo.svg"})
    insert_image(%{path: "images/alt/gone.jpg", deleted_at: DateTime.utc_now()})
    insert_image(%{path: "images/alt/raw.jpg", status: :unprocessed})

    ids = Enum.map(AltText.missing(), & &1.id)
    assert Enum.sort(ids) == Enum.sort([bare.id, blank.id, half.id])
    assert AltText.missing_count() == 3
    assert AltText.missing_languages(half) == ["no"]
    assert AltText.missing_languages(bare) == ["en", "no"]
  end

  test "sends a mid-sized rendition, not the original" do
    image = insert_image(%{path: "images/alt/sized.jpg"})
    # The default config's sizes; the smallest of them at least 512px wide.
    assert AltText.rendition(image) in Map.values(image.sizes)
    refute AltText.rendition(image) == image.sizes["thumb"]
  end

  defp stub_reply(text) do
    test = self()

    Req.Test.stub(Brando.AI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "id" => "r",
        "object" => "response",
        "status" => "completed",
        "model" => "gpt-4o-mini",
        "output" => [
          %{
            "type" => "message",
            "id" => "m",
            "role" => "assistant",
            "status" => "completed",
            "content" => [%{"type" => "output_text", "text" => text, "annotations" => []}]
          }
        ],
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
      })
    end)
  end

  test "describes an image in every language it lacks, in one request" do
    Brando.AIStub.configure()
    image = insert_image(%{path: "images/alt/harbour.jpg", title: %{"en" => "Oslo harbour"}})
    place_file(image)
    stub_reply(~s({"en": "A ferry leaving Oslo harbour at dusk", "no": "En ferje forlater Oslo havn i skumringen"}))

    assert {:ok, %{values: values}} = AltText.describe(image.id)
    assert values == %{"en" => "A ferry leaving Oslo harbour at dusk", "no" => "En ferje forlater Oslo havn i skumringen"}

    assert_received {:request, %{"input" => [%{"content" => parts}]}}
    assert Enum.any?(parts, &(&1["type"] == "input_image" and &1["image_url"] =~ "data:image/jpeg;base64,"))
    text = Enum.find_value(parts, &(&1["type"] == "input_text" && &1["text"]))
    assert text =~ ~s["en" (English)]
    assert text =~ ~s["no" (Norsk)]
    assert text =~ "one JSON object"
    assert text =~ "The image's title: Oslo harbour"
  end

  test "asks only for the missing languages, showing the ones it has" do
    Brando.AIStub.configure()
    image = insert_image(%{path: "images/alt/half.jpg", alt: %{"en" => "A ferry at dusk"}})
    place_file(image)
    stub_reply(~s({"no": "En ferje i skumringen", "en": "ignored, not asked for"}))

    assert {:ok, %{values: %{"no" => "En ferje i skumringen"} = values}} = AltText.describe(image.id)
    refute Map.has_key?(values, "en")

    assert_received {:request, %{"input" => [%{"content" => parts}]}}
    text = Enum.find_value(parts, &(&1["type"] == "input_text" && &1["text"]))
    refute text =~ ~s["en" (English)]
    assert text =~ "English: A ferry at dusk"
  end

  test "reads replies in a code fence, plain text for one language, and refuses the rest" do
    assert AltText.parse(~s(```json\n{"no": "Hei"}\n```), ["no"]) == {:ok, %{"no" => "Hei"}}
    assert AltText.parse(~s("Just the text"), ["no"]) == {:ok, %{"no" => "Just the text"}}
    assert AltText.parse("not json", ["no", "en"]) == {:error, :invalid_response}
    assert AltText.parse(~s({"en": ""}), ["en"]) == {:error, :empty_response}
  end

  test "a missing file fails the suggestion with a reason, instead of retrying" do
    Brando.AIStub.configure()
    Brando.AIStub.reply("never asked")
    user = Factory.insert(:random_user)
    image = insert_image(%{path: "images/alt/nowhere.jpg"})

    {:ok, 1} = Suggestions.enqueue([%{schema: Image, id: image.id, title: "nowhere.jpg"}], "en", user, field: :alt)

    assert [%{status: :failed, error: error}] = Suggestions.list_open("en", [:alt])
    assert error == Brando.AI.error_message(:image_file_missing)
  end

  test "bulk alt text waits for review, and accepting merges it into the image's languages" do
    Brando.AIStub.configure()
    user = Factory.insert(:random_user)
    image = insert_image(%{path: "images/alt/fjord.jpg", alt: %{"en" => "Rowing on a fjord"}})
    place_file(image)
    stub_reply(~s({"no": "To personer ror på en stille fjord"}))

    {:ok, 1} = Suggestions.enqueue([%{schema: Image, id: image.id, title: "fjord.jpg"}], "en", user, field: :alt)

    assert [%{status: :pending, values: %{"no" => "To personer ror på en stille fjord"}} = suggestion] =
             Suggestions.list_open("en", [:alt])

    # The Content SEO list is not given image suggestions.
    assert Suggestions.list_open("en", [:meta_description, :meta_title]) == []
    assert Brando.Repo.get!(Image, image.id).alt == %{"en" => "Rowing on a fjord"}

    assert {:ok, _} = Suggestions.accept(suggestion.id, %{"no" => "To personer ror på en fjord"}, user)

    assert Brando.Repo.get!(Image, image.id).alt == %{
             "en" => "Rowing on a fjord",
             "no" => "To personer ror på en fjord"
           }
  end
end
