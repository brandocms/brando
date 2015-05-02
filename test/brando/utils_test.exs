defmodule Brando.UtilsTest do
  use ExUnit.Case, async: true
  use Plug.Test
  import Brando.Utils
  alias Brando.UtilsTest.TestStruct

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
    assert(slugify("special characters (#?@$%^*) are also ASCII") == "special-characters-at-are-also-ascii")
  end

  test "slugify & -> and" do
    assert(slugify("tom & jerry") == "tom-jerry")
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
    assert f =~ ".jpg"
  end

  test "to_string_map/1" do
    test_struct = %TestStruct{}
    test_map = %{"a" => "a", "b" => "b"}
    assert to_string_map(nil) == nil
    assert to_string_map(test_struct) == test_map
    assert to_string_map(test_map) == test_map
  end

  test "split_path/1" do
    assert split_path("test/dir/filename.jpg") == {"test/dir", "filename.jpg"}
    assert split_path("filename.jpg") == {"", "filename.jpg"}
  end

  test "split_filename/1" do
    assert split_filename("filename.jpg") == {"filename", ".jpg"}
    assert split_filename("file name.jpg") == {"file name", ".jpg"}
    assert split_filename("filename") == {"filename", ""}
    assert split_filename("test/filename.jpg") == {"filename", ".jpg"}
  end

  test "maybe/2" do
    assert maybe(nil, &String.upcase/1) == nil
    assert maybe("hello", &String.upcase/1) == "HELLO"
  end

  test "unique_filename/1" do
    filename = "testing.jpg"
    refute unique_filename(filename) == filename
  end

  test "to_iso8601/1" do
    dt = %Ecto.DateTime{year: 2014, month: 1, day: 1,
                        hour: 12, min: 0, sec: 0}
    assert to_iso8601(dt) == "2014-01-01T12:00:00Z"
  end
end