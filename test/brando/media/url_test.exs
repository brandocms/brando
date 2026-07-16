defmodule Brando.Media.URLTest do
  use ExUnit.Case, async: true

  alias Brando.Media.URL

  test "resolves paths below the configured media URL" do
    assert URL.base() == "/media"
    assert URL.resolve(nil) == "/media"
    assert URL.resolve("images/photo.jpg") == "/media/images/photo.jpg"
  end
end
