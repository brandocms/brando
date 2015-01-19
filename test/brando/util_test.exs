defmodule Brando.UtilTest do
  use ExUnit.Case
  use Plug.Test
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

  test "secure_compare/2" do
    assert secure_compare("asdf", "asdf")
    refute secure_compare("asdf", "dfsa")
  end

  test "add_js/2" do
    conn = conn(:get, "/")
    assert conn.assigns[:js_extra] == nil
    conn = conn |> add_js("test.js")
    assert conn.assigns[:js_extra] == "test.js"
    conn = conn |> add_js(["test1.js", "test2.js"])
    assert conn.assigns[:js_extra] == ["test1.js", "test2.js"]
  end

  test "add_css/2" do
    conn = conn(:get, "/")
    assert conn.assigns[:css_extra] == nil
    conn = conn |> add_css("test.css")
    assert conn.assigns[:css_extra] == "test.css"
    conn = conn |> add_css(["test1.css", "test2.css"])
    assert conn.assigns[:css_extra] == ["test1.css", "test2.css"]
  end
end