defmodule Brando.SSG.TargetPathsTest do
  use ExUnit.Case, async: true

  alias Brando.SSG.TargetPaths

  test "reads only the deleting lines that start with the nonce, decoding rsync's escapes" do
    output =
      Enum.join(
        [
          "N0NCE *deleting  |a b",
          "N0NCE *deleting  |new\\#012line",
          "N0NCE *deleting  |back\\#134#012slash",
          "N0NCE *deleting  | lead ",
          "N0NCE *deleting  |dir/",
          "N0NCE cd+++++++++|made/",
          "*deleting  |forged",
          "OTHER *deleting  |forged",
          "remote says: N0NCE *deleting  |forged"
        ],
        "\n"
      )

    assert TargetPaths.parse_listing(output, "N0NCE") == ["a b", "new\nline", "back\\#012slash", " lead ", "dir/"]
  end

  test "keeps a directory entry's contents, and a file entry's name" do
    keep = [".well-known/", "robots.txt"]

    assert TargetPaths.kept?(".well-known/", keep)
    assert TargetPaths.kept?(".well-known/acme/x", keep)
    assert TargetPaths.kept?("robots.txt", keep)
    refute TargetPaths.kept?(".well-known", keep)
    refute TargetPaths.kept?("robots.txt.bak", keep)
    refute TargetPaths.kept?(".well-knownx/", keep)
  end

  test "writes rules a name matches only itself by, kept first and every other path protected" do
    rules = [".well-known/"] |> TargetPaths.keep_rules() |> IO.iodata_to_binary()
    assert rules == "P /.well-known/***\0"

    build = Path.join(System.tmp_dir!(), "target-paths-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(build, "assets"))
    File.write!(Path.join(build, "assets/app.js"), "")
    on_exit(fn -> File.rm_rf(build) end)

    plan = TargetPaths.plan(build, ["old.html", "st*r", "b\\c", "kept[1]/x", "../up"], ["kept[1]/"])

    assert plan.upload == ["assets/", "assets/app.js"]
    assert plan.deletable == ["b\\c", "old.html", "st*r"]

    assert IO.iodata_to_binary(plan.rules) ==
             "P /kept\\[1]/***\0R /b\\c\0R /old.html\0R /st\\*r\0P *\0"
  end

  test "summarises the top-level entries with their files" do
    assert TargetPaths.top_level(["a/", "a/b/", "a/b/c", "a/d", "x.html"], ["x.html"]) == [
             %{name: "a/", files: 2, kept: false},
             %{name: "x.html", files: 1, kept: true}
           ]
  end
end
