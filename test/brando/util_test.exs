defmodule Brando.UtilTest do
  use ExUnit.Case
  import Brando.Util
  alias Brando.UtilTest.TestStruct

  defmodule TestStruct do
    defstruct a: "a", b: "b"
  end

  test "slugify basic stripping/no ending dash" do
    assert(slugify("This is basic functionality!!!    ") == "this-is-basic-functionality")
  end

  test "slugify no starting dash" do
    assert(slugify("-This is basic functionality!!!    ") == "this-is-basic-functionality")
  end

  test "slugify straße" do
    assert slugify("straße") == "strasse"
  end

  test "slugify strips symbols" do
    assert slugify("Is ♬ ♫ ♪ ♩ a melody or just noise?") == "is-a-melody-or-just-noise"
  end

  test "slugify strips accents" do
    assert slugify("Àddîñg áçćèńtš tô Éñgłïśh íš śīłłÿ!") == "adding-accents-to-english-is-silly"
  end

  test "slugify special characters" do
    assert(slugify("special characters (#?@$%^*) are also ASCII") == "special-characters-are-also-ascii")
  end

  test "slugify & -> and" do
    assert(slugify("tom & jerry") == "tom-and-jerry")
  end

  test "slugify strip extraneous dashes" do
    assert(slugify("so - just one then?") == "so-just-one-then")
  end

  test "slugify_filename/1" do
    assert(slugify_filename("testing with spaces.jpeg") == "testing-with-spaces.jpeg")
    assert(slugify_filename("-start æøå-.jpeg") == "start-aeoa.jpeg")
  end

  test "random_filename/1" do
    f = random_filename("original-filename.jpg")
    refute(f == "original-filename.jpg")
    assert(String.contains?(f, ".jpg"))
  end

  test "to_string_map/1" do
    test_struct = %TestStruct{}
    test_map = %{"a" => "a", "b" => "b"}
    assert to_string_map(nil) == nil
    assert to_string_map(test_struct) == test_map
    assert to_string_map(test_map) == test_map
  end
end