defmodule Brando.Villain.BarePictureTagTest do
  use ExUnit.Case, async: true

  # The options block is optional in the grammar, so the tag has to render
  # without one
  test "{% picture %} renders without options" do
    image = %Brando.Images.Image{
      path: "images/ferry.jpg",
      sizes: %{"xlarge" => "images/xlarge/ferry.jpg"},
      width: 300,
      height: 200,
      config_target: "default"
    }

    html = Brando.Villain.parse_and_render("{% picture image %}", Liquex.Context.new(%{"image" => image}))

    assert [_picture] = html |> Floki.parse_fragment!() |> Floki.find("picture")
  end
end
