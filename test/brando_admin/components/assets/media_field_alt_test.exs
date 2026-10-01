defmodule BrandoAdmin.Components.Assets.MediaFieldAltTest do
  # An image field says what its alt text is, or that it has none; a use's
  # own alt text (a picture block's) is the one shown.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.Assets.MediaField

  defp render(image, attrs \\ %{}) do
    Map.merge(
      %{id: "f", type: :image, asset: image, kind: "entry_field", presentation: :block, __changed__: nil},
      attrs
    )
    |> MediaField.field()
    |> rendered_to_string()
  end

  defp image(alt),
    do: %Brando.Images.Image{
      id: 1,
      status: :processed,
      path: "images/a.jpg",
      width: 10,
      height: 10,
      alt: alt,
      sizes: %{"small" => "images/small/a.jpg", "xlarge" => "images/xlarge/a.jpg"}
    }

  test "an image without alt text says so" do
    assert render(image(%{})) =~ "No alt text"
  end

  test "a block's own alt text is shown instead of the library's" do
    html = render(image(%{}), %{alt_override: "An orange shelf"})

    assert html =~ "An orange shelf"
    refute html =~ "No alt text"
  end
end
