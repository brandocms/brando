defmodule Brando.TagsTest do
  use ExUnit.Case, async: true
  alias Brando.Tag

  test "split_tags/1" do
    assert Tag.split_tags(%{}) == %{}

    assert Tag.split_tags(%{"tags" => "a tag,another,yet another"}) ==
             %{"tags" => ["a tag", "another", "yet another"]}

    assert Tag.split_tags(%{"tags" => "test, testing"}) == %{"tags" => ["test", "testing"]}
    assert Tag.split_tags(%{"test" => "hello"}) == %{"test" => "hello"}
  end
end
