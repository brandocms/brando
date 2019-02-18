defmodule Brando.Types.ImageTest do
  use ExUnit.Case
  alias Brando.Type.Image

  @raw ~s({"width":null,"title":null,"sizes":{"thumb":"images/avatars/thumb/27i97a.) <>
         ~s(jpeg","medium":"images/avatars/medium/27i97a.jpeg"},"path":") <>
         ~s(images/avatars/27i97a.jpeg","optimized":false,"height":null,"focal":{"y":50,"x":50},"credits":"Credits"})

  @result %Image{
    credits: "Credits",
    optimized: false,
    path: "images/avatars/27i97a.jpeg",
    title: nil,
    sizes: %{
      "medium" => "images/avatars/medium/27i97a.jpeg",
      "thumb" => "images/avatars/thumb/27i97a.jpeg"
    }
  }

  @struct %Image{}

  test "cast" do
    assert Image.cast(@raw) == {:ok, @result}
    assert Image.cast(@struct) == {:ok, @struct}
  end

  test "blank?" do
    assert Image.blank?(@raw) == @struct
  end

  test "load" do
    assert Image.load(@raw) == {:ok, @result}
  end

  test "dump" do
    assert Image.dump(@result) == {:ok, @raw}
  end
end
