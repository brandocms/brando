defmodule Brando.Content.Definition.ArchiveTest do
  use ExUnit.Case, async: false
  alias Brando.Content.Definition.Archive

  defp zip(files) do
    {:ok, {_, binary}} =
      :zip.create(~c"modules.zip", Enum.map(files, fn {name, body} -> {String.to_charlist(name), body} end), [:memory])

    binary
  end

  defp unsafe_zip(name) do
    # OTP's writer normalizes absolute paths too. Patch equal-length header
    # names so this fixture represents a hostile archive from another tool.
    placeholder = String.duplicate("x", byte_size(name))
    :binary.replace(zip([{placeholder, "invalid"}]), placeholder, name, [:global])
  end

  test "accepts a directory ZIP and preserves authored files when advancing its baseline" do
    source = "# Keep this comment\n" <> File.read!("test/fixtures/definitions/hero.exs.txt")
    binary = zip([{"modules/hero.exs", source}, {"modules/.DS_Store", "metadata"}, {"__MACOSX/._hero.exs", "metadata"}])
    assert {:ok, archive} = Archive.read(binary)
    assert archive.files == %{"hero.exs" => source}

    bundle =
      Map.merge(archive.bundle, %{
        "source" => "scope",
        "baseline" => %{"modules" => %{"hero-test" => "digest"}},
        "references" => %{}
      })

    assert {:ok, updated} = Archive.update(archive, bundle)
    assert {:ok, read} = Archive.read(updated)
    assert read.files["hero.exs"] == source
    assert read.bundle == bundle
  end

  test "rejects traversal, absolute paths, duplicate paths and unsupported files" do
    for name <- ["../escape.exs", "/escape.exs", "folder/../../escape.exs", "folder\\escape.exs", "C:/escape.exs"] do
      assert {:error, message} = Archive.read(unsafe_zip(name))
      assert message =~ "unsafe archive path"
    end

    assert {:error, message} = Archive.read(zip([{"duplicate.exs", "one"}, {"duplicate.exs", "two"}]))
    assert message =~ "ZIP filenames"
    assert {:error, message} = Archive.read(zip([{"run.sh", "echo no"}]))
    assert message =~ "only DSL"
    assert {:error, _} = Archive.read(zip([{"a.exs", "file"}, {"a.exs/b.exs", "nested"}]))
  end

  test "rejects invalid archives and bounded expansion before reading definitions" do
    assert {:error, _} = Archive.read("not a ZIP")
    assert {:error, _} = Archive.read(:binary.copy("x", Archive.max_bytes() + 1))
    assert {:error, message} = Archive.read(zip([{"large.heex", :binary.copy("x", 20_000_001)}]))
    assert message =~ "20 MB"
    assert {:error, message} = Archive.read(zip(Enum.map(1..501, &{"#{&1}.exs", ""})))
    assert message =~ "500"
  end

  test "uploaded DSL is read as literals and template paths stay within the bundle" do
    source = File.read!("test/fixtures/definitions/hero.exs.txt")

    assert {:error, message} =
             Archive.read(
               zip([{"hero.exs", String.replace(source, "uid \"hero-test\"", "uid System.get_env(\"HOME\")")}])
             )

    assert message =~ "only literals"
    source = Regex.replace(~r/  template :heex, .*/, source, "  template_file :heex, \"../outside.heex\"")
    assert {:error, message} = Archive.read(zip([{"hero.exs", source}]))
    assert message =~ "escapes"
  end

  test "checks actual inflation even when both ZIP headers understate the expanded size" do
    binary = zip([{"large.heex", :binary.copy("x", 100_000)}])
    {central_offset, _} = :binary.match(binary, <<"PK", 1, 2>>)

    binary =
      Enum.reduce([22, central_offset + 24], binary, fn offset, binary ->
        before = binary_part(binary, 0, offset)
        rest = binary_part(binary, offset + 4, byte_size(binary) - offset - 4)
        <<before::binary, 1::little-32, rest::binary>>
      end)

    assert {:error, message} = Archive.read(binary)
    assert message =~ "exceeds its declared size"
  end
end
