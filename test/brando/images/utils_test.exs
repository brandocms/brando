defmodule Brando.Images.UtilsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Plug.Test
  use RouterHelper

  import Brando.Images.Utils

  test "get_sized_path/2 binary" do
    assert get_sized_path("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "get_sized_path/2 binary with .jpeg ext" do
    assert get_sized_path("test/dir/filename.jpeg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "get_sized_path/2 atom" do
    assert get_sized_path("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end

  test "get_sized_dir" do
    assert get_sized_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb"
    assert get_sized_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb"
  end

  test "media_path" do
    assert media_path() == Brando.config(:media_path)
    assert media_path(nil) == Brando.config(:media_path)
    assert media_path("images") == Path.join(Brando.config(:media_path), "images")
  end
end
