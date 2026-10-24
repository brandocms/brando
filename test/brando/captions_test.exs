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

  # Centre a caption, then delete its text: the paragraph keeps its style
  test "a caption is present only when it has text" do
    refute Captions.present?(~s(<p style="text-align: center;"></p>))
    refute Captions.present?(~s(<p style="text-align: center;"><br></p>))
    refute Captions.present?("<p>&nbsp;</p><p> </p>")
    refute Captions.present?("<p><strong></strong></p>")
    assert Captions.present?("<p>&amp;</p>")
    assert Captions.present?("Fish & chips")
    assert Captions.normalize(~s(<p style="text-align: center;"></p>)) == nil
  end

  # Plain fields (alt text, credits, a video's title) share the check: what
  # looks like a tag there is text
  test "plain text that looks like a tag is present" do
    assert Captions.present?("<untitled>")
    assert Captions.present?("a < b")
    refute Captions.present?("   ")
  end

  test "text/1 keeps blocks apart and inline formatting together" do
    assert Captions.text("<p>Tour</p><p>film</p>") == "Tour film"
    assert Captions.text("<p>Tour fil<em>m</em></p>") == "Tour film"
    assert Captions.text("<p>Tour<br>film</p>") == "Tour film"
    assert Captions.text("<h2>Tour</h2><ul><li>film</li><li>&amp; more</li></ul>") == "Tour film & more"
    assert Captions.text("<p>  Tour \n film </p>") == "Tour film"
    assert Captions.text("<p></p>") == nil
    assert Captions.text(nil) == nil
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
    test "a plain override that looks like a tag is an override" do
      override =
        %GalleryObjectOverride{}
        |> GalleryObjectOverride.cast_override(%{
          "object_id" => "1",
          "object_type" => "video",
          "title" => "<untitled>",
          "alt" => "<Untitled>"
        })
        |> Ecto.Changeset.apply_changes()

      refute override.use_default_title
      refute override.use_default_alt
    end

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
