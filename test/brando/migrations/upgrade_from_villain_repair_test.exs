defmodule Brando.Migrations.UpgradeFromVillainRepairTest do
  # A pre-blocks site taken through every later upgrade template
  # (Brando.UpgradeFromVillainCase, which has the setup and helpers):
  # repairing its legacy media weeks after the conversion.
  use Brando.UpgradeFromVillainCase

  alias Brando.Utils
  alias Mix.Tasks.Brando.Repair.LegacyMedia, as: RepairTask

  describe "repairing legacy media safely, weeks after the conversion" do
    test "an entry whose blocks no longer line up with Villain's is left alone" do
      %{page: page_id, state: state} = lost_media()

      # An editor adds another "Jobb med oss" block above the one that lost
      # its pictures: by position, Villain's block 1 is the new one now
      [[jobs]] = rows("SELECT id FROM content_modules WHERE class = 'jobs'")

      [[block]] =
        insert!(
          "INSERT INTO content_blocks (uid, type, module_id, active, collapsed, inserted_at, updated_at) VALUES ($1, 'module', $2, true, false, now(), now())",
          [Utils.generate_uid(), jobs]
        )

      for name <- ~w(pic pic2 pic3 pic5) do
        rows(
          "INSERT INTO content_refs (uid, name, block_id, data, sequence, active, collapsed, inserted_at, updated_at) VALUES ($1, $2, $3, $4, 0, true, false, now(), now())",
          [Utils.generate_uid(), name, block, %{"type" => "picture", "data" => %{}}]
        )
      end

      rows("UPDATE pages_blocks SET sequence = sequence + 1 WHERE entry_id = $1", [page_id])
      rows("INSERT INTO pages_blocks (entry_id, block_id, sequence) VALUES ($1, $2, 0)", [page_id, block])

      before = state.()
      assert [_ | _] = repairs = repairs()

      for {_ref, action} <- repairs do
        assert {:skip, "3 blocks in Villain, 4 now"} = action
      end

      assert {nil, _output} = run_task(RepairTask, [])
      assert state.() == before
    end

    test "a wrapped block in another module, or a ref of another type now, is left alone" do
      %{page: page_id, state: state} = lost_media()

      wrapper = root_block(page_id, 2)
      rows("UPDATE content_refs SET data = jsonb_set(data, '{type}', '\"text\"') WHERE block_id = $1", [wrapper])
      before = state.()

      assert Enum.all?(
               repairs(),
               &match?({_, {:skip, "block 3 › a picture block in Villain, its content ref is not a picture now"}}, &1)
             )

      run_task(RepairTask, [])
      assert state.() == before

      [[jobs]] = rows("SELECT id FROM content_modules WHERE class = 'jobs'")
      rows("UPDATE content_blocks SET module_id = $1 WHERE id = $2", [jobs, wrapper])

      assert Enum.all?(
               repairs(),
               &match?({_, {:skip, "block 3 › a picture block in Villain, now not in a Legacy Content Wrapper"}}, &1)
             )
    end

    test "an entry, block or gallery edited since the conversion is left alone" do
      %{page: page_id, state: state} = lost_media()
      before = state.()

      # An editor cleared a picture, or removed gallery images: the entry's
      # save moves its edited_at
      rows("UPDATE pages SET edited_at = $1 WHERE id = $2", [utc_in(60), page_id])
      assert Enum.all?(repairs(), &match?({_, {:skip, "edited " <> _}}, &1))
      run_task(RepairTask, [])
      assert state.() == before

      rows("UPDATE pages SET edited_at = NULL WHERE id = $1", [page_id])
      rows("UPDATE content_blocks SET edited_at = $1 WHERE id = $2", [utc_in(86_400), root_block(page_id, 2)])
      [[gallery_id]] = rows("SELECT gallery_id FROM content_refs WHERE name = 'gallery' AND gallery_id IS NOT NULL")
      rows("UPDATE galleries_gallery_objects SET edited_at = $1 WHERE gallery_id = $2", [utc_in(86_400), gallery_id])

      assert %{
               "ref content" => {:skip, "its block was edited since the conversion"},
               "ref gallery" => {:skip, "its gallery was edited since the conversion"},
               "ref pic" => {:make_image, _}
             } =
               Map.new(repairs())
    end

    test "an image to make is left alone once the trash may have emptied one an editor deleted since" do
      %{page: page_id, images: images, state: state} = lost_media()

      # The conversion 40 days ago. pic5 was linked; an editor trashed its
      # image, and emptying the trash 30 days later deleted it and nilled
      # the ref, with no trace left
      for {table, columns} <- [
            {"schema_migrations", ~w(inserted_at)},
            {"content_blocks", ~w(inserted_at updated_at edited_at)},
            {"galleries_gallery_objects", ~w(inserted_at updated_at edited_at)}
          ] do
        set = Enum.map_join(columns, ", ", &"#{&1} = #{&1} - interval '40 days'")
        rows("UPDATE #{table} SET #{set}")
      end

      rows("DELETE FROM images WHERE id = $1", [images.linked])
      before = state.()

      doubt =
        "the conversion is more than 30 days old, and the trash is emptied after 30 days: " <>
          "media an editor deleted since may be gone without a trace, and this could bring it back"

      assert %{"ref pic5" => {:skip, ^doubt}, "ref pic" => {:skip, ^doubt}, "ref pic3" => {:link_image, _, _}} =
               Map.new(repairs())

      run_task(RepairTask, [])

      assert [
               ["pic", nil, false, nil],
               ["pic2", nil, false, nil],
               ["pic3", "images/site/posts/by-size.png", false, nil] | _
             ] =
               ref_media(page_id)

      refute state.() == before

      # Within 30 days, an image an editor trashed is still in the trash: its
      # ref is left alone, the others made
      rows("UPDATE schema_migrations SET inserted_at = inserted_at + interval '35 days'")
      rows("UPDATE images SET deleted_at = $1 WHERE path = 'images/site/posts/trashed.jpg'", [utc_in(0)])

      assert %{"ref pic2" => {:skip, "its image went to the trash " <> _}, "ref pic" => {:make_image, _}} =
               Map.new(repairs())
    end

    test "a gallery an editor emptied in its own form is not filled again" do
      %{state: state} = lost_media()

      # The gallery form saves the gallery, not the page, and leaves no
      # object to carry a time
      [[gallery_id]] = rows("SELECT gallery_id FROM content_refs WHERE name = 'gallery' AND gallery_id IS NOT NULL")
      rows("DELETE FROM galleries_gallery_objects WHERE gallery_id = $1", [gallery_id])
      before = state.()

      assert %{"ref gallery" => {:skip, "its gallery is not what the conversion left in it" <> _}} = Map.new(repairs())
      run_task(RepairTask, [])
      assert {_, _, [], _, _} = state.()
      assert elem(state.(), 2) == elem(before, 2)
    end

    test "an entry edited between planning and writing is left alone" do
      %{page: page_id, state: state} = lost_media()
      before = state.()

      # An editor picks an image for pic, saves, clears it and saves again
      edit = fn -> rows("UPDATE pages SET edited_at = $1 WHERE id = $2", [utc_in(60), page_id]) end

      assert Enum.all?(repairs(before_write: edit), &match?({_, {:skip, "edited " <> _}}, &1))
      assert state.() == before
    end

    test "a video trashed since the conversion is not made again" do
      %{about: about} = lost_media()

      video_block = root_block(about, 3)

      [[ref_id, video_id]] =
        rows("SELECT id, video_id FROM content_refs WHERE block_id = $1 AND name = 'video'", [video_block])

      # The ref lost its video, and an editor put the video in the trash
      rows("UPDATE content_refs SET video_id = NULL WHERE id = $1", [ref_id])
      rows("UPDATE videos SET deleted_at = $1 WHERE id = $2", [utc_in(0), video_id])
      videos = rows("SELECT id, deleted_at FROM videos ORDER BY id")

      assert %{"ref video" => {:skip, "its video went to the trash " <> _}} = Map.new(repairs())
      run_task(RepairTask, [])
      assert rows("SELECT video_id FROM content_refs WHERE id = $1", [ref_id]) == [[nil]]
      assert rows("SELECT id, deleted_at FROM videos ORDER BY id") == videos
    end

    test "an image picked while the repair runs stays" do
      %{page: page_id, images: images} = lost_media()

      pick = fn ->
        rows(
          "UPDATE content_refs SET image_id = $1 WHERE name = 'pic' AND block_id = $2",
          [images.known, root_block(page_id, 0)]
        )
      end

      assert %{"ref pic" => {:skip, "media was picked for it while the repair ran"}, "ref pic2" => {:make_image, _}} =
               Map.new(repairs(before_write: pick))

      assert [["pic", "images/site/gallery/known.jpg", false, nil] | _] = ref_media(page_id)
    end

    test "without the conversion's time nothing is written, and --converted-at gives it", %{copies: copies} do
      %{state: state} = lost_media()
      before = state.()
      [[migrated_at]] = rows("SELECT max(inserted_at) FROM schema_migrations")
      File.rm!(Path.join(copies, "#{version() + 133}_brando_133_transfer_ref_media_data.exs"))

      assert Enum.all?(repairs(), &match?({_, {:skip, "can't tell when brando_133 ran" <> _}}, &1))
      run_task(RepairTask, [])
      assert state.() == before

      assert {nil, output} = run_task(RepairTask, ["--converted-at", NaiveDateTime.to_iso8601(migrated_at)])
      assert Enum.any?(output, &(&1 =~ "count as editors'"))
      assert findings() == []
    end
  end
end
