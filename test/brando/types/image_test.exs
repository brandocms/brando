defmodule Brando.Types.ImageTest do
  use ExUnit.Case
  alias Brando.Type.Image

  @raw "{\"title\":null,\"sizes\":{\"thumb\":\"images/avatars/thumb/27i97a.jpeg\",\"medium\":\"images/avatars/medium/27i97a.jpeg\"},\"path\":\"images/avatars/27i97a.jpeg\",\"optimized\":false,\"credits\":\"Credits\"}"
  @result %Image{credits: "Credits", optimized: false, path: "images/avatars/27i97a.jpeg",
                 sizes: %{"medium" => "images/avatars/medium/27i97a.jpeg",
                          "thumb" => "images/avatars/thumb/27i97a.jpeg"}, title: nil}
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