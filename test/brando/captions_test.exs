defmodule Brando.CaptionsTest do
  use ExUnit.Case, async: true

  alias Brando.Captions
  alias Brando.Villain.Blocks.GalleryObjectOverride

  test "an empty rich-text document is no caption" do
    refute Captions.present?(nil)
    refute Captions.present?("<p></p>")
    refute Captions.present?(" <p><br></p> ")
    assert Captions.present?("<p>A</p>")
  end

  test "normalize/1 stores nil for empty and strips unsafe markup" do
    assert Captions.normalize("<p></p>") == nil

    assert Captions.normalize("<p><strong>A</strong> <a href=\"/x\">b</a></p>") ==
             "<p><strong>A</strong> <a href=\"/x\">b</a></p>"

    normalized = Captions.normalize(~s|<p onclick="x()">A</p><script>alert(1)</script>|)
    refute normalized =~ "onclick"
    refute normalized =~ "<script"
    assert normalized =~ "A"
  end

  test "library text is escaped unless it already holds markup" do
    assert Captions.library_html("Fish & <chips>") == "Fish &amp; &lt;chips&gt;"
    assert Captions.library_html("<p>Old <em>rich</em></p><script>x</script>") == "<p>Old <em>rich</em></p>x"
    assert Captions.library_html("") == nil
  end

  test "safe_preview/2 prefers the placement caption, sanitized" do
    assert Captions.safe_preview("<p><em>A</em><script>x</script></p>", "Library") == {:safe, "<p><em>A</em>x</p>"}
    assert Captions.safe_preview("<p></p>", "A & B") == {:safe, "A &amp; B"}
    assert Captions.safe_preview(nil, nil) == nil
  end

  test "plain/1 strips markup to one line" do
    assert Captions.plain("<p><strong>North</strong> wall</p>") == "North wall"
    assert Captions.plain("<p></p>") == nil
  end

  describe "GalleryObjectOverride.cast_override/2" do
    test "derives each flag from its text when the params do not set it" do
      override =
        %GalleryObjectOverride{}
        |> GalleryObjectOverride.cast_override(%{
          "object_id" => "1",
          "object_type" => "video",
          "title" => "",
          "caption" => "<p>Rich</p>",
          "alt" => "<p></p>"
        })
        |> Ecto.Changeset.apply_changes()

      assert override.caption == "<p>Rich</p>"
      refute override.use_default_caption
      assert override.use_default_title
      assert override.use_default_alt
      assert override.use_default_credits
    end

    test "keeps a flag the params set explicitly" do
      override =
        %GalleryObjectOverride{}
        |> GalleryObjectOverride.cast_override(%{
          "object_id" => "1",
          "object_type" => "image",
          "title" => "Kept but inactive",
          "use_default_title" => "true"
        })
        |> Ecto.Changeset.apply_changes()

      assert override.use_default_title
    end

    test "is how the gallery block casts its overrides" do
      data =
        %Brando.Villain.Blocks.GalleryBlock.Data{}
        |> Brando.Villain.Blocks.GalleryBlock.Data.changeset(%{
          "gallery_object_overrides" => [%{"object_id" => "1", "object_type" => "image", "title" => "<p>A</p>"}]
        })
        |> Ecto.Changeset.apply_changes()

      assert [%{title: "<p>A</p>", use_default_title: false}] = data.gallery_object_overrides
    end
  end
end
