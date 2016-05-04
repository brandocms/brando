defmodule Brando.UtilsTest do
  use ExUnit.Case, async: true
  use Plug.Test
  import Brando.Utils
  alias Brando.UtilsTest.TestStruct

  defmodule TestStruct do
    defstruct a: "a", b: "b"
  end

  test "slugify basic stripping/no ending dash" do
    assert slugify("This is basic functionality!!!    ")
           == "this-is-basic-functionality"
  end

  test "slugify no starting dash" do
    assert slugify("-This is basic functionality!!!    ")
           == "this-is-basic-functionality"
  end

  test "slugify straße" do
    assert slugify("straße")
           == "strasse"
  end

  test "slugify strips symbols" do
    assert slugify("Is ♬ ♫ ♪ ♩ a melody or just noise?")
           == "is-a-melody-or-just-noise"
  end

  test "slugify strips accents" do
    assert slugify("Àddîñg áçćèńtš tô Éñgłïśh íš śīłłÿ!")
           == "adding-accents-to-english-is-silly"
  end

  test "slugify special characters" do
    assert slugify("special characters (#?@$%^*) are also ASCII")
           == "special-characters-atdollar-are-also-ascii"
  end

  test "slugify & -> and" do
    assert slugify("tom & jerry") == "tom-and-jerry"
  end

  test "slugify strip extraneous dashes" do
    assert slugify("so - just one then?") == "so-just-one-then"
  end

  test "slugify_filename/1" do
    assert slugify_filename("testing with spaces.jpeg")
           == "testing-with-spaces.jpeg"
    assert slugify_filename("-start æøå-.jpeg")
           == "start-aeoeaa.jpeg"
  end

  test "random_filename/1" do
    f = random_filename("original-filename.jpg")
    refute f == "original-filename.jpg"
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

  test "unique_filename/1" do
    filename = "testing.jpg"
    refute unique_filename(filename) == filename
  end

  test "to_iso8601/1" do
    dt = %Ecto.DateTime{year: 2014, month: 1, day: 1, hour: 12, min: 0, sec: 0}
    assert to_iso8601(dt) == "2014-01-01T12:00:00Z"
  end

  test "media_url/1" do
    assert media_url("test") == "/media/test"
    assert media_url(nil) == "/media"
  end

  test "active_path?/2" do
    conn = conn(:get, "/some/link")
    assert active_path?(conn, "/some/link")
    refute active_path?(conn, "/some/other/link")
  end

  test "img_url/2" do
    img = %{
      path: "original/path/file.jpg",
      sizes: %{"thumb" => "images/thumb/file.jpg"}
    }
    assert img_url(img, :thumb)
           == "images/thumb/file.jpg"
    assert img_url(nil, :thumb, [default: "default.jpg", prefix: "prefix"])
           == "thumb/default.jpg"
    assert img_url(nil, :thumb, [default: "default.jpg"])
           == "thumb/default.jpg"
    assert img_url(img, :thumb, [default: "default.jpg", prefix: "prefix"])
           == "prefix/images/thumb/file.jpg"
    assert img_url(img, :thumb, [default: "default.jpg"])
           == "images/thumb/file.jpg"
    assert img_url(img, "thumb", [default: "default.jpg"])
           == "images/thumb/file.jpg"
    assert img_url(img, :original)
           == "original/path/file.jpg"
    assert img_url(img, :original, prefix: "prefix")
           == "prefix/original/path/file.jpg"


    assert_raise ArgumentError, fn ->
      img_url(img, :notasize, [default: "default.jpg"])
    end
  end

  test "get_now" do
    now = get_now()
    assert is_bitstring(now)
    assert String.length(now) == 19
  end

  test "get_date_now" do
    now = get_date_now()
    assert is_bitstring(now)
    assert String.length(now) == 10
  end

  test "split_by" do
    records = [
      %{name: "John", gender: :male},
      %{name: "Alice", gender: :female},
      %{name: "Liza", gender: :female},
      %{name: "Karen", gender: :female}
    ]
    result = split_by(records, :gender)
    assert length(result[:male]) == 1
    assert length(result[:female]) == 3
  end

  test "get_page_title" do
    assert get_page_title(%{assigns: %{page_title: "Test"}}) == "MyApp | Test"
    assert get_page_title(%{}) == "MyApp"
  end

  test "host_and_media_url" do
    mock_conn = %{port: 80, scheme: "http", host: "brando.com"}
    assert host_and_media_url(mock_conn) == "http://brando.com/media"
    mock_conn = %{port: 8000, scheme: "https", host: "brando.com"}
    assert host_and_media_url(mock_conn) == "https://brando.com:8000/media"
  end
end
