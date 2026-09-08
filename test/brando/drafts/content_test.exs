defmodule Brando.Drafts.ContentTest do
  use ExUnit.Case, async: true
  alias Brando.DraftFixtures
  alias Brando.Drafts.Content

  test "editor initialization is equivalent to the saved content" do
    saved = DraftFixtures.payload()
    captured = DraftFixtures.initialized(saved)
    refute Brando.Drafts.checksum(saved) == Brando.Drafts.checksum(captured)
    assert Content.checksum(saved) == Content.checksum(captured)
  end

  test "content, IDs, invalid values, contracts and every meaningful list order still count as edits" do
    original = DraftFixtures.initialized(DraftFixtures.payload())
    block = ["blocks", "blocks", Access.at(0), "block"]

    changes = [
      put_in(original, ["main", "title"], "Edited"),
      put_in(original, ["main", "sequence"], 9),
      put_in(original, ["main", "image_id"], nil),
      update_in(original, ["blocks", "blocks"], &Enum.reverse/1),
      update_in(original, block ++ ["children"], &Enum.reverse/1),
      update_in(original, block ++ ["vars"], &Enum.reverse/1),
      update_in(original, block ++ ["refs"], &Enum.reverse/1),
      update_in(original, block ++ ["table_rows"], &Enum.reverse/1),
      update_in(original, block ++ ["block_identifiers"], &Enum.reverse/1),
      put_in(original, block ++ ["block_identifiers", Access.at(0), "identifier_id"], 999),
      put_in(original, block ++ ["vars", Access.at(0), "value"], ""),
      put_in(original, block ++ ["refs", Access.at(0), "data", "data", "text"], "Changed text"),
      put_in(original, block ++ ["refs", Access.at(1), "gallery_id"], "invalid ID"),
      put_in(original, block ++ ["uid"], "replaced-block"),
      put_in(original, ["modules", "local:1", "version"], 2),
      update_in(original, ["transformers", "items"], &Enum.reverse/1),
      put_in(original, ["transformers", "items", Access.at(0), "title"], "Changed row")
    ]

    Enum.each(changes, fn changed -> refute Content.checksum(original) == Content.checksum(changed) end)
  end

  test "explicit gallery overrides and unknown override fields cannot disappear from comparison" do
    original = DraftFixtures.initialized(DraftFixtures.payload())

    path = [
      "blocks",
      "blocks",
      Access.at(0),
      "block",
      "refs",
      Access.at(1),
      "data",
      "data",
      "gallery_object_overrides",
      Access.at(0)
    ]

    for attrs <- [
          %{"use_default_title" => false},
          %{"title" => ""},
          %{"title" => "Dormant text"},
          %{"controls" => false, "use_default_controls" => false},
          %{"object_id" => "invalid"},
          %{"object_id" => ""},
          %{"object_id" => 0},
          %{"future_setting" => true}
        ] do
      changed = update_in(original, path, &Map.merge(&1, attrs))
      refute Content.checksum(original) == Content.checksum(changed)
    end
  end

  test "unrelated creator and sequence fields are not stripped" do
    original = %{"main" => %{"settings" => %{"creator_id" => nil, "sequence" => 0}}, "blocks" => %{}}
    refute Content.checksum(original) == Content.checksum(put_in(original, ["main", "settings", "creator_id"], 7))
    refute Content.checksum(original) == Content.checksum(put_in(original, ["main", "settings", "sequence"], 1))
  end
end
