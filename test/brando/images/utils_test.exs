defmodule Brando.Images.UtilsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Plug.Test
  use RouterHelper

  import Brando.Images.Utils

  test "size_dir/2 binary" do
    assert size_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "size_dir/2 atom" do
    assert size_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end

  test "media_path" do
    assert media_path() == Brando.config(:media_path)
    assert media_path(nil) == Brando.config(:media_path)
    assert media_path("images") == Path.join(Brando.config(:media_path), "images")
  end
end
