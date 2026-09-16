defmodule Brando.Content.Transfer.ArchiveTest do
  use ExUnit.Case, async: true
  alias Brando.Content.Transfer.Archive

  defp archive(files) do
    {:ok, {_, binary}} =
      :zip.create(~c"content.zip", Enum.map(files, fn {path, body} -> {String.to_charlist(path), body} end), [:memory])

    binary
  end

  test "untrusted paths, malformed manifests, definition-only archives and unsupported versions fail safely" do
    for files <- [
          [{"../content.json", "{}"}],
          [{"/content.json", "{}"}],
          [{"content.json", "not json"}],
          [{"modules.lock.json", "{}"}],
          [{"content.json", "[]"}],
          [{"content.json", "{}"}],
          [{"content.json", ~s({"format":"brando-content","version":99})}],
          [{"content.json", ~s({"format":"brando-content","version":1,"id":"x","source":null})}],
          [{"content.json", "{}"}, {"content.json", "{}"}]
        ] do
      assert {:error, _} = files |> archive() |> Archive.read()
    end
  end

  test "invalid archive bytes return an actionable error" do
    assert {:error, message} = Archive.read("not zip")
    assert message =~ "ZIP"
  end
end
