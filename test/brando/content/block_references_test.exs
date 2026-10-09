defmodule Brando.Content.BlockReferencesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Content.BlockReferences
  alias Brando.Content.Usage
  alias Brando.Factory
  alias Brando.Repo

  # Blocks a site still has after their Blueprint left the app, or whose
  # source names a module that is no entry's block join: no entry owns them,
  # and nothing that resolves owners raises.
  test "a root from a removed Blueprint, or from a module without an entry, belongs to no entry" do
    gone = Repo.insert!(%Block{type: :module, source: "Elixir.App.Gone.Blocks", uid: Brando.Utils.generate_uid()})
    not_a_join = Repo.insert!(%Block{type: :module, source: "Elixir.Brando.Pages.Page", uid: Brando.Utils.generate_uid()})
    child = Repo.insert!(%Block{type: :module, parent_id: gone.id, uid: Brando.Utils.generate_uid()})
    file = Repo.insert!(%Brando.Files.File{filename: "gone.pdf", filesize: 1, config_target: "default"})
    video = Factory.insert(:video)
    Factory.insert(:ref, block_id: child.id, file_id: file.id)
    Factory.insert(:ref, block_id: not_a_join.id, video_id: video.id)

    ids = [gone.id, not_a_join.id, child.id]
    assert BlockReferences.join_schema("Elixir.App.Gone.Blocks") == nil
    assert BlockReferences.join_schema(Brando.Pages.Page) == nil
    assert BlockReferences.join_schema(nil) == nil
    assert {Brando.Pages.Page.Blocks, Brando.Pages.Page} = BlockReferences.join_schema("Elixir.Brando.Pages.Page.Blocks")

    assert BlockReferences.list_root_block_ids_by_source(ids) == %{}
    assert BlockReferences.list_entries_for_block_ids(ids) == %{}
    assert BlockReferences.reject_blocks_belonging_to_entry(ids, nil) == %{}

    # File replacement's chain
    assert file.id
           |> BlockReferences.list_block_ids_using_file()
           |> BlockReferences.list_root_block_ids_by_source()
           |> BlockReferences.list_entry_ids_for_root_blocks_by_source() == %{}

    assert BlockReferences.list_entry_ids_for_root_blocks_by_source(%{App.Gone.Blocks => [gone.id]}) == %{}

    # "Used in" names no one; nothing raises.
    assert Usage.list(:file, [file.id]) == %{}
    assert Usage.list(:video, [video.id]) == %{}
    assert is_list(Usage.used_ids(:file))
  end
end
