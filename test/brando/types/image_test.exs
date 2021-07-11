defmodule Brando.Types.ImageTest do
  use ExUnit.Case
  alias Brando.Images.Image

  @raw %{
    "height" => 292,
    "width" => 300,
    "credits" => "Credits",
    "path" => "images/avatars/27i97a.jpeg",
    "title" => nil,
    "sizes" => %{
      "medium" => "images/avatars/medium/27i97a.jpeg",
      "thumb" => "images/avatars/thumb/27i97a.jpeg"
    }
  }

  @result %Image{
    alt: nil,
    credits: "Credits",
    focal: %Brando.Images.Focal{x: 50, y: 50},
    height: 292,
    path: "images/avatars/27i97a.jpeg",
    sizes: %{
      "medium" => "images/avatars/medium/27i97a.jpeg",
      "thumb" => "images/avatars/thumb/27i97a.jpeg"
    },
    title: nil,
    width: 300
  }

  @struct %Image{}

  test "cast" do
    assert Image.cast(@raw) == {:ok, {:update, @raw}}
    assert Image.cast(@struct) == {:ok, @struct}
  end

  test "load" do
    assert Image.load(@raw) == {:ok, @result}
  end

  test "dump" do
    assert Image.dump(@result) == {:ok, @result}
  end
end
