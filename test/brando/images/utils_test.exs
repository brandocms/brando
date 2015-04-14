defmodule Brando.Images.UtilsTest do
  use ExUnit.Case, async: true
  import Brando.Images.Utils

  test "size_dir/2 binary" do
    assert size_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end
  test "size_dir/2 atom" do
    assert size_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end
end