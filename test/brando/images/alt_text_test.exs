defmodule Brando.Images.AltTextTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Images.AltText
  alias Brando.Images.Image
  alias Brando.SEO.Suggestions

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)

  defp insert_image(attrs) do
    Factory.insert(:image, Map.merge(%{status: :processed, alt: nil}, attrs))
  end

  # Puts the fixture where the image's rendition is read from.
  defp place_file(image) do
    target = Path.join(Brando.Tenant.Storage.current_media_root(), AltText.rendition(image))
    File.mkdir_p!(Path.dirname(target))
    File.cp!(@fixture, target)
  end

  test "lists processed images without alt text, leaving out SVGs and deleted ones" do
    bare = insert_image(%{path: "images/alt/bare.jpg"})
    blank = insert_image(%{path: "images/alt/blank.jpg", alt: "  "})
    insert_image(%{path: "images/alt/done.jpg", alt: "A ferry"})
    insert_image(%{path: "images/alt/logo.svg"})
    insert_image(%{path: "images/alt/gone.jpg", deleted_at: DateTime.utc_now()})
    insert_image(%{path: "images/alt/raw.jpg", status: :unprocessed})

    ids = Enum.map(AltText.missing(), & &1.id)
    assert bare.id in ids
    assert blank.id in ids
    assert length(ids) == 2
    assert AltText.missing_count() == 2
  end

  test "sends a mid-sized rendition, not the original" do
    image = insert_image(%{path: "images/alt/sized.jpg"})
    # The default config's sizes; the smallest of them at least 512px wide.
    assert AltText.rendition(image) in Map.values(image.sizes)
    refute AltText.rendition(image) == image.sizes["thumb"]
  end

  test "describes an image by sending it to the model, in the default language" do
    Brando.AIStub.configure()
    image = insert_image(%{path: "images/alt/harbour.jpg", title: "Oslo harbour"})
    place_file(image)
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
            "content" => [
              %{"type" => "output_text", "text" => "\"A ferry leaving Oslo harbour at dusk\"", "annotations" => []}
            ]
          }
        ],
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
      })
    end)

    assert {:ok, %{text: "A ferry leaving Oslo harbour at dusk"}} = AltText.describe(image.id)

    assert_received {:request, %{"input" => [%{"content" => parts}]}}
    assert Enum.any?(parts, &(&1["type"] == "input_image" and &1["image_url"] =~ "data:image/jpeg;base64,"))
    text = Enum.find_value(parts, &(&1["type"] == "input_text" && &1["text"]))
    assert text =~ Brando.AI.language_name(Brando.config(:default_language))
    assert text =~ "The image's title: Oslo harbour"
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

  test "bulk alt text waits for review, and accepting writes it on the image" do
    Brando.AIStub.configure()
    Brando.AIStub.reply("Two people rowing on a calm fjord")
    user = Factory.insert(:random_user)
    image = insert_image(%{path: "images/alt/fjord.jpg"})
    place_file(image)

    {:ok, 1} = Suggestions.enqueue([%{schema: Image, id: image.id, title: "fjord.jpg"}], "en", user, field: :alt)

    assert [%{status: :pending, text: "Two people rowing on a calm fjord"} = suggestion] =
             Suggestions.list_open("en", [:alt])

    # The Content SEO list is not given image suggestions.
    assert Suggestions.list_open("en", [:meta_description, :meta_title]) == []
    assert Brando.Repo.get!(Image, image.id).alt == nil

    assert {:ok, _} = Suggestions.accept(suggestion.id, "Two people rowing on a fjord", user)
    assert Brando.Repo.get!(Image, image.id).alt == "Two people rowing on a fjord"
  end
end
