defmodule BrandoAdmin.Components.Assets.MediaFieldBrowseLabelTest do
  # The library button is named after what it picks. It shares a row with
  # Configure and Upload replacement, so it has to stay short.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.Assets.MediaField

  defp render(type, asset) do
    %{
      id: "f",
      type: type,
      asset: asset,
      kind: "entry_field",
      presentation: :field,
      browse: %Phoenix.LiveView.JS{},
      __changed__: nil
    }
    |> MediaField.field()
    |> rendered_to_string()
  end

  test "an image field offers Select image" do
    image = %Brando.Images.Image{
      id: 1,
      status: :processed,
      path: "images/a.jpg",
      width: 10,
      height: 10,
      alt: %{},
      sizes: %{"small" => "images/small/a.jpg", "xlarge" => "images/xlarge/a.jpg"}
    }

    assert render(:image, image) =~ "Select image"
  end

  # Was a browser test (admin-panel-refinements.spec.js) on an empty field
  # of a Norwegian admin.
  test "a Norwegian image field offers Velg bilde, filled or empty" do
    image = %Brando.Images.Image{
      id: 1,
      status: :processed,
      path: "images/a.jpg",
      width: 10,
      height: 10,
      alt: %{},
      sizes: %{"small" => "images/small/a.jpg", "xlarge" => "images/xlarge/a.jpg"}
    }

    Gettext.with_locale(Brando.Gettext, "no", fn ->
      for asset <- [image, nil], do: assert(render(:image, asset) =~ "Velg bilde")
    end)
  end

  test "a video field offers Select video, filled or empty" do
    video = %Brando.Videos.Video{id: 1, type: :external_file, title: "Listing", source_url: "https://example.com/a.mp4"}

    for asset <- [video, nil] do
      html = render(:video, asset)
      assert html =~ "Select video"
      refute html =~ "Browse library"
      # Uploads are opt-in, and the test config doesn't choose a strategy.
      assert html =~ "Video upload isn&#39;t set up. Use Select video to pick a video from the library or add one by URL."
    end
  end

  test "a file field offers Select file" do
    assert render(:file, nil) =~ "Select file"
  end
end
