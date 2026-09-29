defmodule Brando.Images.DuplicateUploadTest do
  # An upload of a file the library already has can use the existing image
  # instead. Only uploads carry the file's hash; a copy made with "Duplicate"
  # (another crop, say) is never offered.
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.Images

  test "finds the earliest image of the same file, not deleted" do
    first = Factory.insert(:image, content_hash: "abc")
    _second = Factory.insert(:image, content_hash: "abc")
    deleted = Factory.insert(:image, content_hash: "abc", deleted_at: DateTime.utc_now())
    upload = Factory.insert(:image, content_hash: "abc")

    assert Images.find_duplicate(upload).id == first.id
    refute Images.find_duplicate(upload).id == deleted.id
  end

  test "an image without a hash, or with a hash of its own, has no duplicate" do
    Factory.insert(:image, content_hash: "abc")

    assert Images.find_duplicate(Factory.insert(:image, content_hash: nil)) == nil
    assert Images.find_duplicate(Factory.insert(:image, content_hash: "other")) == nil
  end
end
