defmodule Brando.Mugshots.UtilsTest do
  use ExUnit.Case
  import Brando.Mugshots.Utils

  test "size_dir/2 binary" do
    assert size_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end
  test "size_dir/2 atom" do
    assert size_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end
end