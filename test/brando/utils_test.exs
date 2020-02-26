defmodule Brando.UtilsTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Brando.Utils
  import ExUnit.CaptureIO

  alias Brando.UtilsTest.TestStruct

  defmodule TestStruct do
    defstruct a: "a", b: "b"
  end

  test "slugify basic stripping/no ending dash" do
    assert slugify("This is basic functionality!!!    ") == "this-is-basic-functionality"
  end

  test "slugify no starting dash" do
    assert slugify("-This is basic functionality!!!    ") == "this-is-basic-functionality"
  end

  test "slugify straße" do
    assert slugify("straße") == "strasse"
  end

  test "slugify strips symbols" do
    assert slugify("Is ♬ ♫ ♪ ♩ a melody or just noise?") == "is-♬-♫-♪-♩-a-melody-or-just-noise"
  end

  test "slugify strips accents" do
    assert slugify("Àddîñg áçćèńtš tô Éñgłïśh íš śīłłÿ!") == "adding-accents-to-english-is-silly"
  end

  test "slugify special characters" do
    assert slugify("special characters (#?@$%^*) are also ASCII") ==
             "special-characters-atdollar-are-also-ascii"
  end

  test "slugify & -> and" do
    assert slugify("tom & jerry") == "tom-and-jerry"
  end

  test "slugify strip extraneous dashes" do
    assert slugify("so - just one then?") == "so-just-one-then"
  end

  test "slugify_filename/1" do
    assert slugify_filename("testing with spaces.jpeg") == "testing-with-spaces.jpeg"
    assert slugify_filename("-start æøå-.jpeg") == "start-aeoeaa.jpeg"
    assert slugify_filename("testing.JPG") == "testing.jpg"
  end

  test "random_filename/1" do
    f = random_filename("original-filename.jpg")
    refute f == "original-filename.jpg"
    assert f =~ ".jpg"

    f = random_filename("original-filename.JPG")
    refute f =~ ".JPG"
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

  test "media_url/1" do
    assert media_url("test") == "/media/test"
    assert media_url(nil) == "/media"
  end

  test "active_path?/2" do
    conn = conn(:get, "/some/link")
    assert active_path?(conn, "/some/link") == true
    assert active_path?(conn, "/some/*") == true
    assert active_path?(conn, "/some/other/link") == false
    assert active_path?(conn, "/some/other/*") == false

    conn = conn(:get, "/some/link/that/is/really/long")
    assert active_path?(conn, "/some/*") == true
    assert active_path?(conn, "/some/test/*") == false
  end

  test "img_url/2" do
    img = %{
      path: "original/path/file.jpg",
      sizes: %{"thumb" => "images/thumb/file.jpg"}
    }

    broken_img = %{
      path: "original/path/file.jpg",
      sizes: nil
    }

    assert capture_io(:stderr, fn -> img_url(broken_img, :xlarge) end) =~
             "Wrong size key for img_url function."

    assert img_url(img, :thumb) == "images/thumb/file.jpg"
    assert img_url(nil, :thumb, default: "default.jpg", prefix: "prefix") == "thumb/default.jpg"
    assert img_url(nil, :thumb, default: "default.jpg") == "thumb/default.jpg"

    assert img_url(img, :thumb, default: "default.jpg", prefix: "prefix") ==
             "prefix/images/thumb/file.jpg"

    assert img_url(img, :thumb, default: "default.jpg") == "images/thumb/file.jpg"
    assert img_url(img, "thumb", default: "default.jpg") == "images/thumb/file.jpg"
    assert img_url(img, :original) == "original/path/file.jpg"
    assert img_url(img, :original, prefix: "prefix") == "prefix/original/path/file.jpg"

    assert capture_io(:stderr, fn -> img_url(img, :notasize, default: "default.jpg") end) =~
             "Wrong size key for img_url function."
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
    assert get_page_title(%{assigns: %{page_title: "Test"}}) == "Firma | Test"
    assert get_page_title(%{}) == "Firma | Velkommen!"
  end

  test "host_and_media_url" do
    assert host_and_media_url() == "http://localhost/media"
  end

  test "https_url" do
    mock_conn = %{port: 80, scheme: "http", host: "brando.com", request_path: "/hello"}
    assert https_url(mock_conn) == "https://brando.com/hello"
  end

  test "human_spaced_number" do
    assert human_spaced_number("10000000") == "10 000 000"
    assert human_spaced_number(10_000_000) == "10 000 000"
  end

  test "human_time" do
    assert human_time(1_000_000_000) == "11 days"
    assert human_time(10_000_000) == "2 hours"
    assert human_time(100_000) == "1 mins"
    assert human_time(1000) == "1 secs"
  end

  test "human_size" do
    assert human_size(100_000_000) == "95 MB"
    assert human_size(1_000_000) == "976 kB"
    assert human_size(10_000) == "10 000 B"
  end

  test "helpers" do
    mock_conn = %{private: %{phoenix_router: RouterHelper.TestRouter}}
    assert helpers(mock_conn) == RouterHelper.TestRouter.Helpers
  end
end
