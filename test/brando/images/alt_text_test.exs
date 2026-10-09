defmodule Brando.Images.AltTextTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase
  use Brando.Test

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

  test "describes an image in every language it lacks, in one request" do
    Brando.AIStub.configure()
    image = insert_image(%{path: "images/alt/harbour.jpg", title: %{"en" => "Oslo harbour"}})
    place_file(image)

    use_cassette "alt_text/every_language" do
      assert {:ok, %{values: values}} = AltText.describe(image.id)

      assert values == %{
               "en" => "A ferry leaving Oslo harbour at dusk",
               "no" => "En ferje forlater Oslo havn i skumringen"
             }

      # One request, with the picture and the prompt.
      assert [%{"messages" => [%{"role" => "user", "content" => [%{"text" => text}, picture]}]}] =
               Brando.AI.Cassette.requests()

      assert %{"type" => "image", "media_type" => "image/jpeg"} = picture
      assert text =~ ~s["en" (English)]
      assert text =~ ~s["no" (Norsk)]
      assert text =~ "one JSON object"
      assert text =~ "The image's title: Oslo harbour"
    end
  end

  test "asks only for the missing languages, showing the ones it has" do
    Brando.AIStub.configure()
    image = insert_image(%{path: "images/alt/half.jpg", alt: %{"en" => "A ferry at dusk"}})
    place_file(image)

    use_cassette "alt_text/missing_language" do
      assert {:ok, %{values: %{"no" => "En ferje i skumringen"} = values}} = AltText.describe(image.id)
      refute Map.has_key?(values, "en")

      assert [%{"messages" => [%{"content" => [%{"text" => text} | _]}]}] = Brando.AI.Cassette.requests()
      refute text =~ ~s["en" (English)]
      assert text =~ "English: A ferry at dusk"
    end
  end

  test "a site's own prompt replaces the default instructions, keeping the reply format" do
    image = %{alt: nil, title: %{"en" => "Oslo harbour"}}

    default = AltText.prompt(image, ["en"])
    assert default =~ "screen reader"
    assert default =~ "never guess"

    own = AltText.prompt(image, ["en"], prompt: "Describe the boats only.")
    assert own =~ "Describe the boats only."
    refute own =~ "screen reader"
    assert own =~ "one JSON object"
    assert own =~ "The image's title: Oslo harbour"
  end

  test "the alt site prompt in config drives the description and its model" do
    Brando.AIStub.configure()

    Brando.Test.Support.put_test_env(
      Brando.AI,
      Keyword.put(Application.get_env(:brando, Brando.AI), :prompts,
        alt: [prompt: "Describe the boats only.", model: "openai:gpt-4o"]
      )
    )

    test = self()

    Brando.AIStub.reply(fn prompt ->
      send(test, {:prompt, prompt})
      ~s({"en": "Two ferries", "no": "To ferjer"})
    end)

    image = insert_image(%{path: "images/alt/boats.jpg"})
    place_file(image)

    assert {:ok, %{values: %{"en" => "Two ferries"}, model: "openai:gpt-4o"}} = AltText.describe(image.id)
    assert_received {:prompt, prompt}
    assert prompt =~ "Describe the boats only."
    refute prompt =~ "screen reader"
  end

  test "reads replies in a code fence, plain text for one language, and refuses the rest" do
    assert AltText.parse(~s(```json\n{"no": "Hei"}\n```), ["no"]) == {:ok, %{"no" => "Hei"}}
    assert AltText.parse(~s("Just the text"), ["no"]) == {:ok, %{"no" => "Just the text"}}
    assert AltText.parse("not json", ["no", "en"]) == {:error, :invalid_response}
    assert AltText.parse(~s({"en": ""}), ["en"]) == {:error, :empty_response}
  end

  test "a reply over the limit is sent back once to be shortened" do
    Brando.AIStub.configure()
    image = insert_image(%{path: "images/alt/long.jpg"})
    place_file(image)
    long = String.duplicate("A very long description of a harbour ", 5)

    Brando.AIStub.reply(fn prompt ->
      if prompt =~ "longer than 125 characters",
        do: ~s({"en": "Boats in Oslo harbour at dusk", "no": "Båter i Oslo havn i skumringen"}),
        else: ~s({"en": "#{long}", "no": "Kort nok"})
    end)

    assert {:ok, %{values: values}} = AltText.describe(image.id)
    assert values == %{"en" => "Boats in Oslo harbour at dusk", "no" => "Kort nok"}
  end

  test "text still over the limit is cut at a clause, never mid-word" do
    short = "A ferry at dusk"
    assert AltText.trim(~s("#{short}")) == short

    clause = "Two people row a small wooden boat across a still fjord at dawn"
    tail = ", with mist over the water and snow-capped mountains rising steeply behind them"
    assert AltText.trim(clause <> tail) == clause <> "."

    # No clause keeps half the limit: cut at a word and mark the cut.
    words = String.duplicate("harbour ", 20)
    cut = AltText.trim("Boats, " <> words)
    assert String.ends_with?(cut, "harbour…")
    assert String.length(cut) <= 126
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

    # The suggestion is generated by a job that runs inline, in this process.
    use_cassette "alt_text/bulk" do
      {:ok, 1} = Suggestions.enqueue([%{schema: Image, id: image.id, title: "fjord.jpg"}], "en", user, field: :alt)
    end

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
