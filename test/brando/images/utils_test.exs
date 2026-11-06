defmodule Brando.Images.UtilsTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  use RouterHelper
  import Brando.Images.Utils

  alias Brando.Images.SvgRoot

  test "get_sized_path/2 binary" do
    assert get_sized_path("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "get_sized_path/2 binary with .jpeg ext" do
    assert get_sized_path("test/dir/filename.jpeg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "get_sized_path/2 atom" do
    assert get_sized_path("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end

  test "get_sized_dir" do
    assert get_sized_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb"
    assert get_sized_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb"
  end

  test "media_path" do
    assert media_path() == Brando.config(:media_path)
    assert media_path(nil) == Brando.config(:media_path)
    assert media_path("images") == Path.join(Brando.config(:media_path), "images")
  end

  describe "svg_size/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "brando_svg_size_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      svg = fn name, doctype ->
        path = Path.join(dir, name)

        File.write!(path, """
        <?xml version="1.0"?>
        #{doctype}
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="20"></svg>
        """)

        path
      end

      {:ok, dir: dir, svg: svg}
    end

    # Audit NV3: a DOCTYPE SYSTEM made the parser read a file on the server
    test "does not read a local file the DOCTYPE names", %{dir: dir, svg: svg} do
      # Malformed, so reading it would fail the parse
      dtd = Path.join(dir, "local.dtd")
      File.write!(dtd, "<!ELEMENT svg ANY")

      assert svg_size(svg.("system.svg", ~s(<!DOCTYPE svg SYSTEM "#{dtd}">))) == %{width: 10, height: 20}
      assert svg_size(svg.("file_uri.svg", ~s(<!DOCTYPE svg SYSTEM "file://#{dtd}">))) == %{width: 10, height: 20}
    end

    test "reads an exported SVG that names the public SVG 1.1 DTD", %{svg: svg} do
      doctype =
        ~s(<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">)

      assert svg_size(svg.("public.svg", doctype)) == %{width: 10, height: 20}
    end

    test "reads the sizes ordinary files declare", %{dir: dir} do
      size = fn content ->
        path = Path.join(dir, "ordinary-#{System.unique_integer([:positive])}.svg")
        File.write!(path, content)
        svg_size(path)
      end

      ns = ~s(xmlns="http://www.w3.org/2000/svg")

      assert size.(~s(<svg #{ns} viewBox="0 0 640 480"/>)) == %{width: 640, height: 480}
      assert size.(~s(<svg #{ns} viewBox="0,0,640,480"></svg>)) == %{width: 640, height: 480}
      assert size.(~s(<svg #{ns} viewBox="  0   0\n640.5 480 "></svg>)) == %{width: 640, height: 480}
      assert size.(~s(<svg #{ns} viewBox='0 0 64 48'></svg>)) == %{width: 64, height: 48}
      assert size.(~s(<svg\n  #{ns}\n  width = "12px"\n  height="34.5"\n></svg>)) == %{width: 12, height: 34}
      assert size.(~s(<svg #{ns} width="12" height="34" viewBox="0 0 1 1"></svg>)) == %{width: 12, height: 34}
      assert size.(~s(<svg:svg xmlns:svg="http://www.w3.org/2000/svg" width="5" height="6"/>)) == %{width: 5, height: 6}
      assert size.(<<0xEF, 0xBB, 0xBF>> <> ~s(<svg #{ns} width="7" height="8"/>)) == %{width: 7, height: 8}

      assert size.(~s(<?xml version="1.0"?>\n<!-- Generator: <svg width="1"> -->\n<svg #{ns} width="9" height="10"/>)) ==
               %{width: 9, height: 10}

      utf16 = :unicode.characters_to_binary(~s(<svg #{ns} width="3" height="4"/>), :utf8, {:utf16, :little})
      assert size.(<<0xFF, 0xFE>> <> utf16) == %{width: 3, height: 4}

      # No size to read: the default
      assert size.(~s(<svg #{ns}></svg>)) == %{width: 300, height: 150}
      assert size.(~s(<svg #{ns} viewBox="nonsense"></svg>)) == %{width: 300, height: 150}
      assert size.(~s(<svg #{ns} width="10"></svg>)) == %{width: 300, height: 150}
      assert size.(~s(<svg #{ns} width="99999999999999" height="1"></svg>)) == %{width: 300, height: 150}
      assert size.("not an svg") == %{width: 300, height: 150}
    end

    test "reads no attribute from a nested element, and only the start of the file", %{dir: dir} do
      path = Path.join(dir, "nested.svg")
      File.write!(path, ~s(<svg><svg width="1" height="2"/></svg>))
      assert svg_size(path) == %{width: 300, height: 150}

      path = Path.join(dir, "late_root.svg")
      File.write!(path, ~s(<!-- #{String.duplicate("x", 70_000)} --><svg width="1" height="2"/>))
      assert svg_size(path) == %{width: 300, height: 150}
    end

    test "an entity declared past a processing instruction is still found" do
      fake_root =
        ~s(<!DOCTYPE svg [<?p ]><svg width="1" height="1"> ?><!ENTITY a "hello">]><svg width="100" height="200"/>)

      lone_quote = ~s(<!DOCTYPE svg [<?p ' ?><!ENTITY a "hello"><?q ' ?>]><svg width="100" height="200"/>)

      assert SvgRoot.parse(fake_root) == {:error, :entities}
      assert SvgRoot.parse(lone_quote) == {:error, :entities}
    end

    test "a processing instruction in the DOCTYPE leaves the root alone" do
      data = ~s(<!DOCTYPE svg [<?p ' ] > ?><!ELEMENT svg ANY>]><svg width="100" height="200"/>)

      assert SvgRoot.parse(data) == {:ok, %{"width" => "100", "height" => "200"}}
    end

    test "refuses entity declarations", %{svg: svg} do
      path = svg.("entity.svg", ~s(<!DOCTYPE svg [<!ENTITY a "aaaa">]>))

      assert_raise ArgumentError, fn -> svg_size(path) end
    end
  end
end
