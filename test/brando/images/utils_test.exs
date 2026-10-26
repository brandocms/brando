defmodule Brando.Images.UtilsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use RouterHelper
  import Brando.Images.Utils

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

    test "refuses entity declarations", %{svg: svg} do
      path = svg.("entity.svg", ~s(<!DOCTYPE svg [<!ENTITY a "aaaa">]>))

      # xmerl refuses them itself where it can, the parse's DTD rules otherwise
      refused? =
        ExUnit.CaptureLog.with_log(fn ->
          try do
            svg_size(path)
            false
          rescue
            _ -> true
          catch
            :exit, _ -> true
          end
        end)
        |> elem(0)

      assert refused?
    end
  end
end
