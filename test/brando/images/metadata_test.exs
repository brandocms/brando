defmodule Brando.Images.MetadataTest do
  use ExUnit.Case, async: true

  alias Brando.Images.Metadata

  test "normalizes supported image extensions" do
    assert Metadata.type("photo.JPEG") == :jpg
    assert Metadata.type("vector.svg") == :svg
    assert Metadata.type("modern.avif") == :avif
    assert Metadata.type("unknown.xyz") == {:error, ".xyz"}
  end

  test "classifies dimensions and image-like maps" do
    assert Metadata.orientation(1200, 800) == "landscape"
    assert Metadata.orientation(800, 800) == "square"
    assert Metadata.orientation(%{width: 800, height: 1200}) == "portrait"
    assert Metadata.orientation(nil) == "unknown"
  end
end
