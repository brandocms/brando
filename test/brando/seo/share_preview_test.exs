defmodule Brando.SEO.SharePreviewTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.SEO.SharePreview

  doctest Brando.SEO.SharePreview

  # `trait :meta`'s meta image size: cropped around the focal point.
  @meta_size %{"size" => "2400x1260", "quality" => 75, "crop" => true}

  defp image(focal),
    do: %Brando.Images.Image{width: 4000, height: 3000, focal: %Brando.Images.Focal{x: elem(focal, 0), y: elem(focal, 1)}}

  describe "crop math" do
    test "a cropping size keeps the band around the focal point, as Sizing cuts it" do
      # Resized to 2400×1800, then 1260 rows around the focal point's 900.
      assert SharePreview.shared_region(image({50, 50}), @meta_size) == {{0.0, 450.0, 4000.0, 2100.0}, true}

      # Near the top, the band stops at the edge rather than running off it.
      assert SharePreview.shared_region(image({50, 10}), @meta_size) == {{0.0, 0.0, 4000.0, 2100.0}, true}
    end

    test "a size without crop keeps the whole image" do
      assert SharePreview.shared_region(image({50, 10}), %{"size" => "2100", "quality" => 65}) ==
               {{0, 0, 4000, 3000}, false}
    end

    test "the focal point's place in a card that centres and cuts the shared image" do
      {region, true} = SharePreview.shared_region(image({50, 10}), @meta_size)

      # Open Graph's 1.91 is a hair wider than the crop's 1.905, so a few rows
      # go top and bottom.
      assert SharePreview.focal_in_card(image({50, 10}), region, SharePreview.ratio(:open_graph)) == {50.0, 14.2}

      # Uncropped, X's 2:1 card cuts the top 500 rows away, focal point and all.
      assert SharePreview.focal_in_card(image({50, 10}), {0, 0, 4000, 3000}, SharePreview.ratio(:x)) == nil
      assert SharePreview.focal_in_card(image({30, 50}), {0, 0, 4000, 3000}, SharePreview.ratio(:x)) == {30.0, 50.0}
    end

    test "a shared URL is shown as it is" do
      assert %{src: "https://cdn.example.com/a.jpg", focal: nil, cropped?: false} =
               SharePreview.frame("https://cdn.example.com/a.jpg", :open_graph)

      assert SharePreview.frame(nil, :x) == nil
    end
  end

  describe "values" do
    setup do
      preserve_cache(:seo)
      Brando.Cache.SEO.set()
      :ok
    end

    test "follow the meta schema, then the SEO settings' fallbacks" do
      page = %Brando.Pages.Page{
        title: "Sommerro",
        meta_title: nil,
        meta_description: "A hotel in the old bathhouse.",
        language: :en
      }

      assert %{title: "Sommerro", search_title: "Sommerro", description: "A hotel in the old bathhouse."} =
               SharePreview.values(Brando.Pages.Page, page, "en")

      # Without a meta schema the share title is the site's fallback, while
      # the search result shows the entry's own title.
      assert %{title: fallback_title, search_title: "Sommerro"} =
               SharePreview.values(Brando.Sites.SEO, %{title: "Sommerro"}, "en")

      assert fallback_title == Brando.Cache.SEO.get("en").fallback_meta_title

      seo = Brando.Cache.SEO.get("en")
      fallback = SharePreview.values(Brando.Pages.Page, %{page | meta_description: nil}, "en")
      assert fallback.description == seo.fallback_meta_description
    end
  end
end
