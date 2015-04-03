defmodule Brando.Images.HelpersTest do
  use ExUnit.Case, async: true
  import Brando.Images.Helpers

  test "img/2" do
    img = %{sizes: %{thumb: "images/thumb/file.jpg"}}
    assert img(img, :thumb) == "images/thumb/file.jpg"
    assert img(nil, :thumb, "default.jpg") == "thumb/default.jpg"
    assert img(img, :thumb, "default.jpg") == "images/thumb/file.jpg"
  end
end