defmodule Brando.UtilsTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  use Plug.Test

  import Brando.Utils
  import ExUnit.CaptureIO

  alias Brando.Factory
  alias Brando.Files
  alias Brando.UtilsTest.TestStruct

  doctest Brando.Utils

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

  test "stringify_keys/1" do
    test_map_atom_keys = %{a: "a", b: %{c: "c", d: "d"}}
    test_map = %{"a" => "a", "b" => %{"c" => "c", "d" => "d"}}
    assert stringify_keys(nil) == nil
    assert stringify_keys(test_map_atom_keys) == test_map
    assert stringify_keys(test_map) == test_map
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

  test "change_basename/2" do
    assert change_basename("old_name.jpg", "new_name") == "new_name.jpg"
  end

  test "try_path/2" do
    assert try_path(%{a: %{b: %{c: :d}}}, [:a, :b, :c]) == :d
    assert try_path(%{a: %{b: %{c: :d}}}, [:a, :b, :d]) == nil
  end

  test "to_atom_map/1" do
    assert to_atom_map(%{"user" => "test", "avatar" => "hello"}) == %{
             user: "test",
             avatar: "hello"
           }
  end

  test "escape_current_url" do
    conn = %Plug.Conn{request_path: "/the-url/?want=it"}
    assert escape_current_url(conn) == "http%3A%2F%2Flocalhost%2Fthe-url%2F%3Fwant%3Dit"
  end

  test "escape_and_prefix_host" do
    conn = %Plug.Conn{request_path: "/"}

    assert escape_and_prefix_host(conn, "something") ==
             "http%3A%2F%2Flocalhost%2Fsomething"
  end

  test "render_title" do
    assert render_title(nil, "hello", nil) == "hello"
    assert render_title("// ", "hello", nil) == "// hello"
    assert render_title("// ", "hello", " //") == "// hello //"
    assert render_title(nil, "hello", " //") == "hello //"
  end

  test "file_url" do
    assert file_url(%Files.File{
             filename: "some/path.jpg",
             config_target: "file:Brando.BlueprintTest.Project:pdf"
           }) == "/media/files/projects/some/path.jpg"

    assert file_url("test") == ""
  end

  test "add_cache_string" do
    assert add_cache_string(cache: nil) == ""
    assert add_cache_string(cache: "test") == "?test"
    assert add_cache_string(cache: ~N[2020-01-01 12:00:00]) == "?1577880000"
  end

  test "unique_filename/1" do
    filename = "testing.jpg"
    refute unique_filename(filename) == filename
  end

  test "get_deps_versions" do
    vs = get_deps_versions()

    assert List.first(vs).app == :brando
  end

  test "changeset_has_no_errors" do
    u1 = Factory.insert(:random_user)
    cs1 = Ecto.Changeset.change(u1)
    assert changeset_has_no_errors(cs1) == {:ok, cs1}
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
      path: "images/file.jpg",
      cdn: false,
      sizes: %{"thumb" => "images/thumb/file.jpg"}
    }

    broken_img = %{
      path: "images/file.jpg",
      cdn: false,
      sizes: nil
    }

    assert capture_io(:stderr, fn -> img_url(broken_img, :xlarge) end) =~
             "Wrong size key for img_url function."

    assert img_url(img, :thumb) == "images/thumb/file.jpg"
    assert img_url(nil, :thumb, default: "default.jpg", prefix: "prefix") == "default.jpg"
    assert img_url(nil, :thumb, default: "default.jpg") == "default.jpg"
    assert img_url("", :thumb, default: "default.jpg") == "default.jpg"

    assert img_url(img, :thumb, default: "default.jpg", prefix: "prefix") ==
             "prefix/images/thumb/file.jpg"

    assert img_url(img, :thumb, default: "default.jpg") == "images/thumb/file.jpg"
    assert img_url(img, "thumb", default: "default.jpg") == "images/thumb/file.jpg"
    assert img_url(img, :original) == "images/file.jpg"
    assert img_url(img, :original, prefix: "prefix") == "prefix/images/file.jpg"

    org_cfg = Brando.config(Brando.Images)

    cdn_cfg = %Brando.CDN.Config{
      enabled: true,
      media_url: "https://cdn.com"
    }

    new_cfg = Keyword.put(org_cfg, :cdn, cdn_cfg)
    Application.put_env(:brando, Brando.Images, new_cfg)

    assert img_url(%{img | cdn: true}, :thumb, prefix: "prefix") ==
             "https://cdn.com/prefix/images/thumb/file.jpg"

    img_without_cdn = %{
      path: "images/file.jpg",
      cdn: true,
      config_target: "image:Brando.BlueprintTest.Project:cover",
      sizes: %{"thumb" => "images/thumb/file.jpg"}
    }

    img_with_cdn = %{
      path: "images/file.jpg",
      cdn: true,
      config_target: "image:Brando.BlueprintTest.Project:cover_cdn",
      sizes: %{"thumb" => "images/thumb/file.jpg"}
    }

    assert img_url(img_without_cdn, :thumb, prefix: "prefix") ==
             "https://cdn.com/prefix/images/thumb/file.jpg"

    assert img_url(img_without_cdn, :original, prefix: "prefix") ==
             "https://cdn.com/prefix/images/file.jpg"

    assert img_url(img_with_cdn, :original, prefix: "prefix") ==
             "https://mycustomcdn.com/prefix/images/file.jpg"

    assert img_url(img_with_cdn, :thumb, prefix: "prefix") ==
             "https://mycustomcdn.com/prefix/images/thumb/file.jpg"

    assert img_url(img_with_cdn, :original) ==
             "https://mycustomcdn.com/images/file.jpg"

    assert img_url(img_with_cdn, :thumb) ==
             "https://mycustomcdn.com/images/thumb/file.jpg"

    Application.put_env(:brando, Brando.Images, org_cfg)

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
      %{name: "John", on_call: false},
      %{name: "Alice", on_call: true},
      %{name: "Liza", on_call: true},
      %{name: "Karen", on_call: true}
    ]

    result = split_by(records, :on_call)
    assert length(result[false]) == 1
    assert length(result[true]) == 3
  end

  test "get_page_title" do
    assert get_page_title(%{assigns: %{language: "en", page_title: "Test"}}) ==
             "CompanyName | Test"

    assert get_page_title(%{assigns: %{language: "en"}}) == "CompanyName | Welcome!"
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
    mock_conn = %{private: %{phoenix_router: BrandoIntegrationWeb.Router}}
    assert helpers(mock_conn) == BrandoIntegrationWeb.Router.Helpers
  end

  test "coerce_struct" do
    simple_map = %{
      "name" => "Test Name",
      "email" => "my@email.com"
    }

    simple_struct = coerce_struct(simple_map, Brando.Users.User)
    assert Map.get(simple_struct, :name) == "Test Name"
    assert Map.get(simple_struct, :email) == "my@email.com"

    assoc_map = %{
      "title" => "My title",
      "uri" => "my-title",
      "creator" => simple_map
    }

    assoc_struct = coerce_struct(assoc_map, Brando.Pages.Page)
    assert Map.get(assoc_struct, :title) == "My title"
    assert Map.get(assoc_struct, :uri) == "my-title"
    assert Map.get(assoc_struct.creator, :name) == "Test Name"
    assert Map.get(assoc_struct.creator, :email) == "my@email.com"

    type_map = %{
      "title" => "My title",
      "uri" => "my-title",
      "status" => "published"
    }

    type_struct = coerce_struct(type_map, Brando.Pages.Page)
    assert Map.get(type_struct, :status, :published)

    limited_struct = coerce_struct(type_map, Brando.Pages.Page, :take_keys)

    assert limited_struct == %{
             title: "My title",
             uri: "my-title",
             status: :published
           }
  end
end
