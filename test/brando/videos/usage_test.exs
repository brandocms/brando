defmodule Brando.Videos.UsageTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Videos

  test "a video is used by the page owning the block it sits in, and by galleries holding it" do
    page = Factory.insert(:page, title: "Om oss")
    Brando.Content.create_identifier(Page, page)

    in_block = Factory.insert(:video)
    in_gallery = Factory.insert(:video)
    unused = Factory.insert(:video)

    source = "Elixir.Brando.Pages.Page.Blocks"
    root = Brando.Repo.insert!(%Block{type: :container, source: source, uid: "rootblock00000000000001"})
    child = Brando.Repo.insert!(%Block{type: :module, source: source, parent_id: root.id, uid: "childblock0000000000001"})
    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: root.id, sequence: 0})
    Factory.insert(:ref, block_id: child.id, video_id: in_block.id)

    gallery = Factory.insert(:gallery)
    Factory.insert(:gallery_object, gallery_id: gallery.id, video_id: in_gallery.id)

    usage = Videos.list_usage([in_block.id, in_gallery.id, unused.id])

    assert [%{label: "Om oss"}] = usage[in_block.id]
    assert [%{label: label}] = usage[in_gallery.id]
    assert label =~ "#{gallery.id}"
    refute Map.has_key?(usage, unused.id)

    {:ok, videos} = Videos.list_videos(%{filter: %{unused: "true"}})
    ids = Enum.map(videos, & &1.id)
    assert unused.id in ids
    refute in_block.id in ids
    refute in_gallery.id in ids
  end
end
