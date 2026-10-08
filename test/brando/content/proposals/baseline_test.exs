defmodule Brando.Content.Proposals.BaselineTest do
  use Brando.ConnCase, async: false
  alias Brando.Content.Proposals.Baseline
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.Catalog
  alias Brando.Drafts.Params
  alias Brando.Pages.Page

  setup do
    c = Brando.ProposalFixtures.context()
    Brando.ProposalFixtures.multi_context(c)
  end

  test "a receipt's snapshot loads back into the entry it was taken from", c do
    entry = Catalog.load!(Page, c.work.id, c.user)
    loaded = Baseline.load(entry, Params.snapshot(entry))

    assert Transfer.entry_fingerprint(loaded) == Transfer.entry_fingerprint(entry)
    assert loaded.title == "Work"
    assert loaded.status == entry.status

    [_, multi] = loaded.entry_blocks
    assert Enum.map(multi.block.children, & &1.uid) == c.child_uids
    [alpha | _] = multi.block.children
    assert Enum.find(alpha.refs, &(&1.name == "clip")).video_id == c.video.id
    assert [%{key: "size", value: "100"}] = Enum.map(alpha.vars, &Map.take(&1, [:key, :value]))
  end

  test "link variables name their entries again", c do
    entry = Catalog.load!(Page, c.work.id, c.user)
    [_, multi] = entry.entry_blocks
    [alpha | _] = multi.block.children
    {:ok, identifier} = Brando.Content.create_identifier(Page, c.identity)

    snapshot =
      update_in(
        Params.snapshot(entry),
        ["entry_blocks", Access.at(1), "block", "children", Access.at(0), "vars"],
        &(&1 ++ [%{"type" => "link", "key" => "case", "label" => %{"en" => "Case"}, "identifier_id" => identifier.id}])
      )

    loaded = Baseline.load(entry, snapshot)
    [_, multi] = loaded.entry_blocks
    [loaded_alpha | _] = multi.block.children
    assert loaded_alpha.uid == alpha.uid
    assert %{identifier: %{title: "Identity"}} = Enum.find(loaded_alpha.vars, &(&1.key == "case"))
  end

  test "without a snapshot, or with one that does not load, the saved entry is used", c do
    entry = Catalog.load!(Page, c.work.id, c.user)
    assert Baseline.load(entry, nil) == entry

    assert ExUnit.CaptureLog.capture_log(fn ->
             assert Baseline.load(entry, %{"status" => %{"no" => "status"}}) == entry
           end) =~ "could not be loaded"
  end
end
