defmodule Mix.Brando.Igniter.FilesTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.Files

  test "plans files without writing and is unchanged after applying and rerunning" do
    contents = "defmodule Studio.Owned do\n  def name, do: :studio\nend"
    igniter = test_project() |> Files.create("lib/studio/owned.ex", contents)

    assert_creates(igniter, "lib/studio/owned.ex")
    refute Map.has_key?(igniter.assigns.test_files, "lib/studio/owned.ex")
    assert igniter.tasks == []

    second = igniter |> apply_igniter!() |> Files.create("lib/studio/owned.ex", contents)
    assert second.issues == []
    assert_unchanged(second)
  end

  test "preserves comments and formatting in equivalent existing Elixir files" do
    existing = "# Application-owned comment\ndefmodule Studio.Owned do\n  def name, do: :studio\nend\n"

    result =
      test_project(files: %{"lib/studio/owned.ex" => existing})
      |> Files.create("lib/studio/owned.ex", "defmodule Studio.Owned do\n def name, do: :studio\nend")

    assert result.issues == []
    assert_unchanged(result)
    assert IgniterCase.source(result, "lib/studio/owned.ex") == existing
  end

  test "blocks a conflict even when yes is selected" do
    existing = "defmodule Studio.Owned do\n  def name, do: :custom\nend"

    result =
      test_project(files: %{"lib/studio/owned.ex" => existing})
      |> Igniter.assign(:yes, true)
      |> Files.create("lib/studio/owned.ex", "defmodule Studio.Owned do\n  def name, do: :studio\nend")

    assert_has_issue(result, &String.contains?(&1, "lib/studio/owned.ex already contains different content"))
    assert_unchanged(result)
    assert IgniterCase.source(result, "lib/studio/owned.ex") == existing
  end

  test "composed writers see pending files and preserve the first writer on conflict" do
    first = test_project() |> Files.create("assets/example.txt", "first")
    repeated = Files.create(first, "assets/example.txt", "first")
    conflicting = Files.create(first, "assets/example.txt", "second")

    assert repeated.issues == []
    assert_has_issue(conflicting, &String.contains?(&1, "already contains different content"))
    assert IgniterCase.source(conflicting, "assets/example.txt") == "first"
    refute Map.has_key?(conflicting.assigns.test_files, "assets/example.txt")
  end

  test "treats Rewrite's trailing newline normalization as equivalent for text" do
    result = test_project(files: %{"assets/owned.txt" => "text\n"}) |> Files.create("assets/owned.txt", "text")
    assert result.issues == []
    assert_unchanged(result)
  end

  test "rejects binary payloads which Rewrite would corrupt with a trailing newline" do
    result = test_project() |> Files.create("assets/owned.png", <<137, 80, 78, 71, 0, 255>>)
    assert_has_issue(result, &String.contains?(&1, "text writer cannot safely write binary"))
    assert_unchanged(result)
  end

  test "rejects generated paths outside the project" do
    for path <- ["../elsewhere.ex", "/tmp/elsewhere.ex", "lib/../../elsewhere.ex"] do
      result = test_project() |> Files.create(path, "# do not write")
      assert_has_issue(result, &String.contains?(&1, "must stay inside the project"))
      assert_unchanged(result)
    end
  end
end
