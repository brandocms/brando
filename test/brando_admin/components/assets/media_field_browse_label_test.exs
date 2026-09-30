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
    image = %Brando.Images.Image{id: 1, status: :processed, path: "images/a.jpg", width: 10, height: 10, alt: %{}}
    assert render(:image, image) =~ "Select image"
  end

  test "a video field offers Select video, filled or empty" do
    video = %Brando.Videos.Video{id: 1, type: :external_file, title: "Listing", source_url: "https://example.com/a.mp4"}

    for asset <- [video, nil] do
      html = render(:video, asset)
      assert html =~ "Select video"
      refute html =~ "Browse library"
      assert html =~ "Use Select video to upload a video with this provider."
    end
  end

  test "a file field offers Select file" do
    assert render(:file, nil) =~ "Select file"
  end
end
